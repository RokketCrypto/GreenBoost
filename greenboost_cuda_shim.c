/*
 * GreenBoost v1.0 — CUDA LD_PRELOAD memory shim
 *
 * Intercepts CUDA memory allocations and redirects allocations above a
 * configurable threshold to cuMemAllocManaged (NVIDIA UVM), enabling
 * transparent DDR4 overflow for CUDA applications.
 *
 * No CUDA SDK headers required — all types and function pointers are
 * defined manually and resolved at runtime via dlopen/dlsym.
 *
 * USAGE:
 *   LD_PRELOAD=/usr/local/lib/libgreenboost_cuda.so  ./your_cuda_app
 *
 * ENVIRONMENT VARIABLES:
 *   GREENBOOST_THRESHOLD_MB  Redirect allocations ≥ this size (default: 512)
 *   GREENBOOST_DEBUG         Set to 1 for verbose logging to stderr
 *
 * PREREQUISITES:
 *   nvidia_uvm.ko must be loaded:  sudo modprobe nvidia_uvm
 *
 * Author  : Ferran Duarri
 * License : GPL v2
 */

#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <pthread.h>

/* ------------------------------------------------------------------ */
/*  Minimal CUDA type definitions (no CUDA SDK headers needed)         */
/* ------------------------------------------------------------------ */

typedef unsigned long long CUdeviceptr;
typedef int                CUresult;
typedef unsigned int       CUmemAttach_flags;

#define CUDA_SUCCESS           0
#define CU_MEM_ATTACH_GLOBAL   0x1u
#define CU_MEM_ATTACH_HOST     0x2u

/* ------------------------------------------------------------------ */
/*  Function pointer types for CUDA symbols                            */
/* ------------------------------------------------------------------ */

typedef CUresult (*pfn_cuMemAlloc_v2)(CUdeviceptr *, size_t);
typedef CUresult (*pfn_cuMemFree_v2)(CUdeviceptr);
typedef CUresult (*pfn_cuMemAllocManaged)(CUdeviceptr *, size_t, CUmemAttach_flags);
typedef CUresult (*pfn_cuMemGetInfo)(size_t *, size_t *);
typedef CUresult (*pfn_cudaMalloc)(void **, size_t);
typedef CUresult (*pfn_cudaFree)(void *);
typedef CUresult (*pfn_cudaMallocManaged)(void **, size_t, unsigned int);

/* ------------------------------------------------------------------ */
/*  Allocation tracker                                                  */
/* ------------------------------------------------------------------ */

#define MAX_TRACKED  65536

struct gb_alloc_entry {
	CUdeviceptr ptr;
	size_t      size;
	int         is_managed;
};

static struct gb_alloc_entry alloc_table[MAX_TRACKED];
static int    alloc_count  = 0;
static pthread_mutex_t table_lock = PTHREAD_MUTEX_INITIALIZER;

/* ------------------------------------------------------------------ */
/*  Global state                                                        */
/* ------------------------------------------------------------------ */

static pfn_cuMemAlloc_v2     real_cuMemAlloc_v2;
static pfn_cuMemFree_v2      real_cuMemFree_v2;
static pfn_cuMemAllocManaged real_cuMemAllocManaged;
static pfn_cuMemGetInfo      real_cuMemGetInfo;
static pfn_cudaMalloc        real_cudaMalloc;
static pfn_cudaFree          real_cudaFree;
static pfn_cudaMallocManaged real_cudaMallocManaged;

/*
 * VRAM headroom: always keep this many bytes free in GPU VRAM for
 * compute buffers, kv-cache, etc. Overflow beyond this goes to DDR4.
 * Override with GREENBOOST_VRAM_HEADROOM_MB (default 1024 = 1 GB).
 */
static size_t vram_headroom_bytes = 1024ULL * 1024 * 1024;
static int    gb_debug            = 0;
static int    initialized         = 0;

#define gb_log(fmt, ...) \
	do { \
		if (gb_debug) \
			fprintf(stderr, "[GreenBoost] " fmt "\n", ##__VA_ARGS__); \
	} while (0)

/* ------------------------------------------------------------------ */
/*  Tracker helpers                                                     */
/* ------------------------------------------------------------------ */

static void gb_track(CUdeviceptr ptr, size_t size, int is_managed)
{
	pthread_mutex_lock(&table_lock);
	if (alloc_count < MAX_TRACKED) {
		alloc_table[alloc_count].ptr        = ptr;
		alloc_table[alloc_count].size       = size;
		alloc_table[alloc_count].is_managed = is_managed;
		alloc_count++;
	}
	pthread_mutex_unlock(&table_lock);
}

static int gb_untrack(CUdeviceptr ptr, struct gb_alloc_entry *out)
{
	int i, found = 0;

	pthread_mutex_lock(&table_lock);
	for (i = 0; i < alloc_count; i++) {
		if (alloc_table[i].ptr == ptr) {
			if (out)
				*out = alloc_table[i];
			/* Remove by swapping with last entry */
			alloc_table[i] = alloc_table[--alloc_count];
			found = 1;
			break;
		}
	}
	pthread_mutex_unlock(&table_lock);
	return found;
}

/* ------------------------------------------------------------------ */
/*  Constructor — runs before main()                                    */
/* ------------------------------------------------------------------ */

__attribute__((constructor))
static void gb_shim_init(void)
{
	void *libcuda;
	const char *env;

	env = getenv("GREENBOOST_VRAM_HEADROOM_MB");
	if (env)
		vram_headroom_bytes = (size_t)atoll(env) * 1024ULL * 1024ULL;

	env = getenv("GREENBOOST_DEBUG");
	if (env && env[0] == '1')
		gb_debug = 1;

	libcuda = dlopen("libcuda.so.1", RTLD_NOW | RTLD_GLOBAL);
	if (!libcuda) {
		fprintf(stderr,
			"[GreenBoost] WARNING: cannot open libcuda.so.1: %s\n",
			dlerror());
		return;
	}

	real_cuMemAlloc_v2     = (pfn_cuMemAlloc_v2)    dlsym(libcuda, "cuMemAlloc_v2");
	real_cuMemFree_v2      = (pfn_cuMemFree_v2)     dlsym(libcuda, "cuMemFree_v2");
	real_cuMemAllocManaged = (pfn_cuMemAllocManaged) dlsym(libcuda, "cuMemAllocManaged");
	/* Try v2 first, fall back to v1 */
	real_cuMemGetInfo      = (pfn_cuMemGetInfo)      dlsym(libcuda, "cuMemGetInfo_v2");
	if (!real_cuMemGetInfo)
		real_cuMemGetInfo  = (pfn_cuMemGetInfo)      dlsym(libcuda, "cuMemGetInfo");
	real_cudaMalloc        = (pfn_cudaMalloc)        dlsym(libcuda, "cudaMalloc");
	real_cudaFree          = (pfn_cudaFree)          dlsym(libcuda, "cudaFree");
	real_cudaMallocManaged = (pfn_cudaMallocManaged) dlsym(libcuda, "cudaMallocManaged");

	if (!real_cuMemAlloc_v2 || !real_cuMemFree_v2) {
		fprintf(stderr,
			"[GreenBoost] WARNING: failed to resolve core CUDA symbols\n");
		return;
	}

	if (!real_cuMemAllocManaged) {
		fprintf(stderr,
			"[GreenBoost] WARNING: cuMemAllocManaged not found — "
			"is nvidia_uvm loaded? (sudo modprobe nvidia_uvm)\n");
	}

	initialized = 1;

	fprintf(stderr,
		"[GreenBoost] v1.0 loaded — vram_headroom=%zuMB debug=%d\n",
		vram_headroom_bytes >> 20, gb_debug);
	fprintf(stderr,
		"[GreenBoost] Policy: VRAM-aware (overflow to DDR4 when VRAM-headroom < request)\n");
	fprintf(stderr,
		"[GreenBoost] UVM overflow  : %s\n",
		real_cuMemAllocManaged ? "available" : "unavailable (load nvidia_uvm)");
	fprintf(stderr,
		"[GreenBoost] VRAM info     : %s\n",
		real_cuMemGetInfo ? "available" : "unavailable");
	fprintf(stderr,
		"[GreenBoost] Combined VRAM : 12 GB physical + up to 51 GB DDR4 via UVM\n");
}

/* ------------------------------------------------------------------ */
/*  Destructor — runs after main() returns                             */
/* ------------------------------------------------------------------ */

__attribute__((destructor))
static void gb_shim_fini(void)
{
	pthread_mutex_lock(&table_lock);
	if (alloc_count > 0) {
		fprintf(stderr,
			"[GreenBoost] WARNING: %d allocations still live at exit\n",
			alloc_count);
	}
	pthread_mutex_unlock(&table_lock);

	gb_log("shim unloaded");
}

/* ------------------------------------------------------------------ */
/*  VRAM-aware overflow decision                                        */
/*  Returns 1 if this allocation should go to DDR4 via UVM.            */
/* ------------------------------------------------------------------ */

static int gb_needs_overflow(size_t bytesize)
{
	size_t free_vram = 0, total_vram = 0;

	if (!real_cuMemGetInfo || !real_cuMemAllocManaged)
		return 0;

	if (real_cuMemGetInfo(&free_vram, &total_vram) != CUDA_SUCCESS)
		return 0;

	/*
	 * Overflow to DDR4 when the allocation would leave less than
	 * vram_headroom_bytes free in VRAM.
	 */
	if (bytesize + vram_headroom_bytes > free_vram) {
		gb_log("VRAM check: req=%zuMB free=%zuMB headroom=%zuMB → OVERFLOW to DDR4",
		       bytesize >> 20, free_vram >> 20, vram_headroom_bytes >> 20);
		return 1;
	}

	gb_log("VRAM check: req=%zuMB free=%zuMB → fits in VRAM",
	       bytesize >> 20, free_vram >> 20);
	return 0;
}

/* ------------------------------------------------------------------ */
/*  cuMemAlloc_v2 override                                              */
/* ------------------------------------------------------------------ */

CUresult cuMemAlloc_v2(CUdeviceptr *dptr, size_t bytesize)
{
	CUresult ret;

	if (!initialized || !real_cuMemAlloc_v2)
		return CUDA_SUCCESS;

	if (gb_needs_overflow(bytesize)) {
		ret = real_cuMemAllocManaged(dptr, bytesize, CU_MEM_ATTACH_GLOBAL);
		if (ret == CUDA_SUCCESS) {
			gb_track(*dptr, bytesize, 1);
			return CUDA_SUCCESS;
		}
		gb_log("cuMemAllocManaged failed (ret=%d), falling back to device alloc",
		       ret);
	}

	ret = real_cuMemAlloc_v2(dptr, bytesize);
	if (ret == CUDA_SUCCESS)
		gb_track(*dptr, bytesize, 0);
	return ret;
}

/* ------------------------------------------------------------------ */
/*  cuMemFree_v2 override                                               */
/* ------------------------------------------------------------------ */

CUresult cuMemFree_v2(CUdeviceptr dptr)
{
	struct gb_alloc_entry entry;

	if (!initialized || !real_cuMemFree_v2)
		return CUDA_SUCCESS;

	if (gb_untrack(dptr, &entry)) {
		gb_log("cuMemFree_v2(ptr=%llx size=%zu MB managed=%d)",
		       (unsigned long long)dptr, entry.size >> 20, entry.is_managed);
	}

	return real_cuMemFree_v2(dptr);
}

/* ------------------------------------------------------------------ */
/*  cudaMalloc override                                                 */
/* ------------------------------------------------------------------ */

CUresult cudaMalloc(void **devPtr, size_t size)
{
	CUresult ret;
	CUdeviceptr dptr = 0;

	if (!initialized || !real_cudaMalloc)
		return CUDA_SUCCESS;

	if (gb_needs_overflow(size)) {
		ret = real_cuMemAllocManaged(&dptr, size, CU_MEM_ATTACH_GLOBAL);
		if (ret == CUDA_SUCCESS) {
			*devPtr = (void *)(uintptr_t)dptr;
			gb_track(dptr, size, 1);
			return CUDA_SUCCESS;
		}
		gb_log("cuMemAllocManaged failed (ret=%d), falling back", ret);
	}

	ret = real_cudaMalloc(devPtr, size);
	if (ret == CUDA_SUCCESS)
		gb_track((CUdeviceptr)(uintptr_t)*devPtr, size, 0);
	return ret;
}

/* ------------------------------------------------------------------ */
/*  cudaFree override                                                   */
/* ------------------------------------------------------------------ */

CUresult cudaFree(void *devPtr)
{
	struct gb_alloc_entry entry;
	CUdeviceptr dptr = (CUdeviceptr)(uintptr_t)devPtr;

	if (!initialized || !real_cudaFree)
		return CUDA_SUCCESS;

	if (gb_untrack(dptr, &entry)) {
		gb_log("cudaFree(ptr=%llx size=%zu MB managed=%d)",
		       (unsigned long long)dptr, entry.size >> 20, entry.is_managed);
	}

	return real_cudaFree(devPtr);
}
