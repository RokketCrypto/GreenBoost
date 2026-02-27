#!/bin/bash
# Комплексный тест виртуальной видеокарты

set -e

echo "=========================================="
echo "Комплексный тест виртуальной видеокарты"
echo "=========================================="
echo ""

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASSED=0
FAILED=0

# Функция для проверки
check() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $1"
        ((PASSED++))
        return 0
    else
        echo -e "${RED}✗${NC} $1"
        ((FAILED++))
        return 1
    fi
}

# Проверка 1: Модуль загружен
echo "1. Проверка загрузки модуля:"
if lsmod | grep -q "^greenboost "; then
    check "Модуль greenboost загружен"
    MODULE_INFO=$(lsmod | grep "^greenboost")
    echo "   Информация: $MODULE_INFO"
else
    check "Модуль greenboost загружен"
    echo "   Загрузите модуль: sudo insmod greenboost.ko"
fi
echo ""

# Проверка 2: Устройство существует
echo "2. Проверка устройства /dev/greenboost:"
if [ -e "/dev/greenboost" ]; then
    check "Устройство /dev/greenboost существует"
    ls -l /dev/greenboost
else
    check "Устройство /dev/greenboost существует"
fi
echo ""

# Проверка 3: Sysfs директория
echo "3. Проверка sysfs интерфейса:"
if [ -d "/sys/class/greenboost" ]; then
    check "Sysfs директория существует"
    echo "   Содержимое:"
    ls -la /sys/class/greenboost/
else
    check "Sysfs директория существует"
fi
echo ""

# Проверка 4: Файл vram_info
echo "4. Проверка файла vram_info:"
if [ -f "/sys/class/greenboost/greenboost/vram_info" ]; then
    check "Файл vram_info существует"
    echo "   Содержимое:"
    cat /sys/class/greenboost/greenboost/vram_info | sed 's/^/   /'
else
    check "Файл vram_info существует"
fi
echo ""

# Проверка 5: Чтение через устройство
echo "5. Чтение информации через /dev/greenboost:"
if [ -r "/dev/greenboost" ]; then
    if timeout 2 cat /dev/greenboost > /tmp/greenboost_test_output 2>&1; then
        check "Успешное чтение из устройства"
        echo "   Содержимое:"
        cat /tmp/greenboost_test_output | sed 's/^/   /'
        rm -f /tmp/greenboost_test_output
    else
        check "Успешное чтение из устройства"
    fi
else
    echo -e "${YELLOW}⚠${NC} Нет прав на чтение устройства (запустите от root)"
fi
echo ""

# Проверка 6: Логи ядра
echo "6. Проверка логов ядра:"
if dmesg | grep -q "greenboost"; then
    check "Найдены записи в логах ядра"
    echo "   Последние записи:"
    dmesg | grep "greenboost" | tail -5 | sed 's/^/   /'
else
    check "Найдены записи в логах ядра"
fi
echo ""

# Проверка 7: Информация о VRAM
echo "7. Проверка информации о VRAM:"
if [ -f "/sys/class/greenboost/greenboost/vram_info" ]; then
    VRAM_INFO=$(cat /sys/class/greenboost/greenboost/vram_info)
    if echo "$VRAM_INFO" | grep -q "16 GB\|16384 MB"; then
        check "Общий объем VRAM = 16 GB"
    else
        echo -e "${YELLOW}⚠${NC} Общий объем VRAM не равен 16 GB (проверьте параметры загрузки модуля)"
    fi
    
    if echo "$VRAM_INFO" | grep -q "6 GB\|6144 MB"; then
        check "Физическая VRAM = 6 GB"
    else
        echo -e "${YELLOW}⚠${NC} Физическая VRAM не равна 6 GB (может быть настроена иначе)"
    fi
    
    if echo "$VRAM_INFO" | grep -q "10 GB\|10240 MB"; then
        check "Виртуальная VRAM = 10 GB"
    else
        echo -e "${YELLOW}⚠${NC} Виртуальная VRAM не равна 10 GB (может быть настроена иначе)"
    fi
fi
echo ""

# Проверка 8: Тест в LXC контейнере (если доступен)
echo "8. Проверка доступности LXC контейнера:"
if command -v lxc-info >/dev/null 2>&1; then
    if lxc-info -n greenboost-test &>/dev/null; then
        check "LXC контейнер greenboost-test существует"
        echo "   Для тестирования в контейнере: sudo lxc-attach -n greenboost-test"
    else
        echo -e "${YELLOW}ℹ${NC} LXC контейнер не создан (опционально)"
    fi
else
    echo -e "${YELLOW}ℹ${NC} LXC не установлен (опционально)"
fi
echo ""

# Итоги
echo "=========================================="
echo "Результаты тестирования:"
echo "=========================================="
echo -e "${GREEN}Пройдено: $PASSED${NC}"
if [ $FAILED -gt 0 ]; then
    echo -e "${RED}Провалено: $FAILED${NC}"
else
    echo -e "${GREEN}Провалено: $FAILED${NC}"
fi
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}Все тесты пройдены успешно!${NC}"
    exit 0
else
    echo -e "${RED}Некоторые тесты провалены${NC}"
    exit 1
fi

