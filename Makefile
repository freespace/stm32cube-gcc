# STM32 Makefile for GNU toolchain and openocd
#
# This Makefile fetches the Cube firmware package from ST's' website.
# This includes: CMSIS, STM32 HAL, BSPs, USB drivers and examples.
#
# Usage:
#	make cube		Download and unzip Cube firmware
#	make program		Flash the board with OpenOCD
#	make openocd		Start OpenOCD
#	make debug		Start GDB and attach to OpenOCD
#	make dirs		Create subdirs like obj, dep, ..
#	make template		Prepare a simple example project in this dir
#
# Copyright	2015 Steffen Vogel
# License	http://www.gnu.org/licenses/gpl.txt GNU Public License
# Author	Steffen Vogel <post@steffenvogel.de>
# Link		http://www.steffenvogel.de
#
# edited for the STM32F4-Discovery

# A name common to all output files (elf, map, hex, bin, lst)
TARGET     = demo

# Take a look into $(CUBE_DIR)/Drivers/BSP for available BSPs
BOARD      = STM32F042K6-Nucleo
BOARD_UC   = STM32F042K6_NUCLEO
BOARD_MC   = STM32F0xx_Nucleo_32

OCDFLAGS   = -f board/st_nucleo_f0.cfg
GDBFLAGS   =

#EXAMPLE   = Templates
EXAMPLE    = Examples/GPIO/GPIO_IOToggle

# MCU family and type in various capitalizations o_O
MCU_FAMILY = stm32f0xx
MCU_FAMILY_UC = STM32F0xx
MCU_LC     = stm32f042x6
MCU_MC     = STM32F042x6
MCU_UC     = STM32F042K6Tx

ARM_CORE	 = cortex-m0

# Your C files from the /src directory
SRCS       = main.c
SRCS      += system_$(MCU_FAMILY).c
SRCS      += $(MCU_FAMILY)_it.c

# Basic HAL libraries
SRCS      += $(MCU_FAMILY)_hal_rcc.c
SRCS 		  += $(MCU_FAMILY)_hal_rcc_ex.c
SRCS      += $(MCU_FAMILY)_hal.c
SRCS      += $(MCU_FAMILY)_hal_cortex.c
SRCS      += $(MCU_FAMILY)_hal_gpio.c

# Directories
OCD_DIR    = /usr/share/openocd/scripts

CUBE_DIR   = cube

BSP_DIR    = $(CUBE_DIR)/Drivers/BSP/$(BOARD_MC)
HAL_DIR    = $(CUBE_DIR)/Drivers/$(MCU_FAMILY_UC)_HAL_Driver
CMSIS_DIR  = $(CUBE_DIR)/Drivers/CMSIS

DEV_DIR    = $(CMSIS_DIR)/Device/ST/$(MCU_FAMILY_UC)

CUBE_URL   = http://www.st.com/st-web-ui/static/active/en/st_prod_software_internet/resource/technical/software/firmware/stm32cubef0.zip

# that's it, no need to change anything below this line!

###############################################################################
# Toolchain

PREFIX     = arm-none-eabi
CC         = $(PREFIX)-gcc
AR         = $(PREFIX)-ar
OBJCOPY    = $(PREFIX)-objcopy
OBJDUMP    = $(PREFIX)-objdump
SIZE       = $(PREFIX)-size
GDB        = $(PREFIX)-gdb

OCD        = openocd

###############################################################################
# Options

# Defines
DEFS       = -D$(MCU_MC) -DUSE_HAL_DRIVER

# Debug specific definitions for semihosting
DEFS       += -DUSE_DBPRINTF

# Include search paths (-I)
INCS       = -Isrc
INCS      += -I$(BSP_DIR)
INCS      += -I$(CMSIS_DIR)/Include
INCS      += -I$(DEV_DIR)/Include
INCS      += -I$(HAL_DIR)/Inc

# Library search paths
LIBS       = -L$(CMSIS_DIR)/Lib

# Compiler flags
CFLAGS     = -Wall -g -std=c99 -Os
CFLAGS    += -mlittle-endian -mcpu=$(ARM_CORE) -mthumb
CFLAGS    += -ffunction-sections -fdata-sections
CFLAGS    += $(INCS) $(DEFS)

# Linker flags
LDFLAGS    = -Wl,--gc-sections -Wl,-Map=$(TARGET).map $(LIBS) -T$(MCU_LC).ld

# Enable Semihosting
LDFLAGS   += --specs=rdimon.specs -lc -lrdimon

# Source search paths
VPATH      = ./src
VPATH     += $(BSP_DIR)
VPATH     += $(HAL_DIR)/Src
VPATH     += $(DEV_DIR)/Source/

OBJS       = $(addprefix obj/,$(SRCS:.c=.o))
DEPS       = $(addprefix dep/,$(SRCS:.c=.d))

# Prettify output
V = 0
ifeq ($V, 0)
	Q = @
	P = > /dev/null
endif

###################################################

.PHONY: all dirs program debug template clean

all: $(TARGET).elf

-include $(DEPS)

dirs: dep obj cube
dep obj src:
	@echo "[MKDIR]   $@"
	$Qmkdir -p $@

obj/%.o : %.c | dirs
	@echo "[CC]      $(notdir $<)"
	$Q$(CC) $(CFLAGS) -c -o $@ $< -MMD -MF dep/$(*F).d

$(TARGET).elf: $(OBJS)
	@echo "[LD]      $(TARGET).elf"
	$Q$(CC) $(CFLAGS) $(LDFLAGS) src/startup_$(MCU_LC).s $^ -o $@
	@echo "[OBJDUMP] $(TARGET).lst"
	$Q$(OBJDUMP) -St $(TARGET).elf >$(TARGET).lst
	@echo "[SIZE]    $(TARGET).elf"
	$(SIZE) $(TARGET).elf

openocd:
	$(OCD) -s $(OCD_DIR) $(OCDFLAGS)

program: all
	$(OCD) -s $(OCD_DIR) $(OCDFLAGS) -c "program $(TARGET).elf verify reset exit"

debug:
	@if ! nc -z localhost 3333; then \
		echo "\n\t[Error] OpenOCD is not running! Start it with: 'make openocd'\n"; exit 1; \
	else \
		$(GDB)  -ex "target extended localhost:3333" \
			-ex "monitor arm semihosting enable" \
			-ex "monitor reset halt" \
			-ex "load" \
			-ex "monitor reset init" \
			$(GDBFLAGS) $(TARGET).elf; \
	fi

cube:
	rm -fr $(CUBE_DIR)
	wget -O /tmp/cube.zip $(CUBE_URL)
	unzip /tmp/cube.zip
	mv STM32Cube* $(CUBE_DIR)
	chmod -R u+w $(CUBE_DIR)
	rm -f /tmp/cube.zip

template: cube src
	cp -ri $(CUBE_DIR)/Projects/$(BOARD)/$(EXAMPLE)/Src/* src
	cp -ri $(CUBE_DIR)/Projects/$(BOARD)/$(EXAMPLE)/Inc/* src
	cp -i $(DEV_DIR)/Source/Templates/gcc/startup_$(MCU_LC).s src
	cp -i $(CUBE_DIR)/Projects/$(BOARD)/$(EXAMPLE)/SW4STM32/$(BOARD_UC)/$(MCU_UC)_FLASH.ld $(MCU_LC).ld

clean:
	@echo "[RM]      $(TARGET).elf"; rm -f $(TARGET).elf
	@echo "[RM]      $(TARGET).map"; rm -f $(TARGET).map
	@echo "[RM]      $(TARGET).lst"; rm -f $(TARGET).lst
	@echo "[RMDIR]   dep"          ; rm -fr dep
	@echo "[RMDIR]   obj"          ; rm -fr obj

