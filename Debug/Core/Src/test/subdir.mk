################################################################################
# Automatically-generated file. Do not edit!
# Toolchain: GNU Tools for STM32 (14.3.rel1)
################################################################################

# Add inputs and outputs from these tool invocations to the build variables 
C_SRCS += \
../Core/Src/test/continuity.c \
../Core/Src/test/insulation.c \
../Core/Src/test/kelvin.c 

OBJS += \
./Core/Src/test/continuity.o \
./Core/Src/test/insulation.o \
./Core/Src/test/kelvin.o 

C_DEPS += \
./Core/Src/test/continuity.d \
./Core/Src/test/insulation.d \
./Core/Src/test/kelvin.d 


# Each subdirectory must supply rules for building sources it contributes
Core/Src/test/%.o Core/Src/test/%.su Core/Src/test/%.cyclo: ../Core/Src/test/%.c Core/Src/test/subdir.mk
	arm-none-eabi-gcc "$<" -mcpu=cortex-m4 -std=gnu11 -g3 -DDEBUG -DUSE_HAL_DRIVER -DSTM32G474xx -c -I../Core/Inc -I../Drivers/STM32G4xx_HAL_Driver/Inc -I../Drivers/STM32G4xx_HAL_Driver/Inc/Legacy -I../Middlewares/Third_Party/FreeRTOS/Source/include -I../Middlewares/Third_Party/FreeRTOS/Source/CMSIS_RTOS_V2 -I../Middlewares/Third_Party/FreeRTOS/Source/portable/GCC/ARM_CM4F -I../Drivers/CMSIS/Device/ST/STM32G4xx/Include -I../Drivers/CMSIS/Include -O0 -ffunction-sections -fdata-sections -Wall -fstack-usage -fcyclomatic-complexity -MMD -MP -MF"$(@:%.o=%.d)" -MT"$@" --specs=nano.specs -mfpu=fpv4-sp-d16 -mfloat-abi=hard -mthumb -o "$@"

clean: clean-Core-2f-Src-2f-test

clean-Core-2f-Src-2f-test:
	-$(RM) ./Core/Src/test/continuity.cyclo ./Core/Src/test/continuity.d ./Core/Src/test/continuity.o ./Core/Src/test/continuity.su ./Core/Src/test/insulation.cyclo ./Core/Src/test/insulation.d ./Core/Src/test/insulation.o ./Core/Src/test/insulation.su ./Core/Src/test/kelvin.cyclo ./Core/Src/test/kelvin.d ./Core/Src/test/kelvin.o ./Core/Src/test/kelvin.su

.PHONY: clean-Core-2f-Src-2f-test

