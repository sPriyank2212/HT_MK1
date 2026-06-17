################################################################################
# Automatically-generated file. Do not edit!
# Toolchain: GNU Tools for STM32 (14.3.rel1)
################################################################################

# Add inputs and outputs from these tool invocations to the build variables 
C_SRCS += \
../Core/Src/drivers/ad7476.c \
../Core/Src/drivers/dac8775.c \
../Core/Src/drivers/dac8830.c \
../Core/Src/drivers/mcp23017.c 

OBJS += \
./Core/Src/drivers/ad7476.o \
./Core/Src/drivers/dac8775.o \
./Core/Src/drivers/dac8830.o \
./Core/Src/drivers/mcp23017.o 

C_DEPS += \
./Core/Src/drivers/ad7476.d \
./Core/Src/drivers/dac8775.d \
./Core/Src/drivers/dac8830.d \
./Core/Src/drivers/mcp23017.d 


# Each subdirectory must supply rules for building sources it contributes
Core/Src/drivers/%.o Core/Src/drivers/%.su Core/Src/drivers/%.cyclo: ../Core/Src/drivers/%.c Core/Src/drivers/subdir.mk
	arm-none-eabi-gcc "$<" -mcpu=cortex-m4 -std=gnu11 -g3 -DDEBUG -DUSE_HAL_DRIVER -DSTM32G474xx -c -I../Core/Inc -I../Drivers/STM32G4xx_HAL_Driver/Inc -I../Drivers/STM32G4xx_HAL_Driver/Inc/Legacy -I../Middlewares/Third_Party/FreeRTOS/Source/include -I../Middlewares/Third_Party/FreeRTOS/Source/CMSIS_RTOS_V2 -I../Middlewares/Third_Party/FreeRTOS/Source/portable/GCC/ARM_CM4F -I../Drivers/CMSIS/Device/ST/STM32G4xx/Include -I../Drivers/CMSIS/Include -O0 -ffunction-sections -fdata-sections -Wall -fstack-usage -fcyclomatic-complexity -MMD -MP -MF"$(@:%.o=%.d)" -MT"$@" --specs=nano.specs -mfpu=fpv4-sp-d16 -mfloat-abi=hard -mthumb -o "$@"

clean: clean-Core-2f-Src-2f-drivers

clean-Core-2f-Src-2f-drivers:
	-$(RM) ./Core/Src/drivers/ad7476.cyclo ./Core/Src/drivers/ad7476.d ./Core/Src/drivers/ad7476.o ./Core/Src/drivers/ad7476.su ./Core/Src/drivers/dac8775.cyclo ./Core/Src/drivers/dac8775.d ./Core/Src/drivers/dac8775.o ./Core/Src/drivers/dac8775.su ./Core/Src/drivers/dac8830.cyclo ./Core/Src/drivers/dac8830.d ./Core/Src/drivers/dac8830.o ./Core/Src/drivers/dac8830.su ./Core/Src/drivers/mcp23017.cyclo ./Core/Src/drivers/mcp23017.d ./Core/Src/drivers/mcp23017.o ./Core/Src/drivers/mcp23017.su

.PHONY: clean-Core-2f-Src-2f-drivers

