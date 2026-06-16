################################################################################
# Automatically-generated file. Do not edit!
# Toolchain: GNU Tools for STM32 (14.3.rel1)
################################################################################

# Add inputs and outputs from these tool invocations to the build variables 
C_SRCS += \
../Core/Src/cards/matrix_card.c 

OBJS += \
./Core/Src/cards/matrix_card.o 

C_DEPS += \
./Core/Src/cards/matrix_card.d 


# Each subdirectory must supply rules for building sources it contributes
Core/Src/cards/%.o Core/Src/cards/%.su Core/Src/cards/%.cyclo: ../Core/Src/cards/%.c Core/Src/cards/subdir.mk
	arm-none-eabi-gcc "$<" -mcpu=cortex-m4 -std=gnu11 -g3 -DDEBUG -DUSE_HAL_DRIVER -DSTM32G474xx -c -I../Core/Inc -I../Drivers/STM32G4xx_HAL_Driver/Inc -I../Drivers/STM32G4xx_HAL_Driver/Inc/Legacy -I../Middlewares/Third_Party/FreeRTOS/Source/include -I../Middlewares/Third_Party/FreeRTOS/Source/CMSIS_RTOS_V2 -I../Middlewares/Third_Party/FreeRTOS/Source/portable/GCC/ARM_CM4F -I../Drivers/CMSIS/Device/ST/STM32G4xx/Include -I../Drivers/CMSIS/Include -O0 -ffunction-sections -fdata-sections -Wall -fstack-usage -fcyclomatic-complexity -MMD -MP -MF"$(@:%.o=%.d)" -MT"$@" --specs=nano.specs -mfpu=fpv4-sp-d16 -mfloat-abi=hard -mthumb -o "$@"

clean: clean-Core-2f-Src-2f-cards

clean-Core-2f-Src-2f-cards:
	-$(RM) ./Core/Src/cards/matrix_card.cyclo ./Core/Src/cards/matrix_card.d ./Core/Src/cards/matrix_card.o ./Core/Src/cards/matrix_card.su

.PHONY: clean-Core-2f-Src-2f-cards

