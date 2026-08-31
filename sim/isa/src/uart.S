.section .text
.globl _start

# 1. 定义 UART 寄存器基地址和字节偏移量
.equ UART_BASE, 0x90001000
.equ UART_RBR,  0x00   # 接收缓冲寄存器 (读)
.equ UART_THR,  0x00   # 发送保持寄存器 (写)
.equ UART_LCR,  0x03   # 通信线控制寄存器
.equ UART_LSR,  0x05   # 通信线状态寄存器 (读)

_start:
    # 2. 初始化 UART: 设置数据帧格式为 8位数据, 无校验, 1位停止位 (8N1)
    li   t0, UART_BASE + UART_LCR
    li   t1, 0x03                # WLS=11 (8位), STB=0 (1位停止位), PS=000 (无校验)
    sb   t1, 0(t0)               # 写入 LCR (字节写入)

    # 3. 输出提示字符串
    lla  a0, msg                 # 获取字符串地址放入 a0
    jal  ra, uart_puts           # 调用打印子程序

    # 4. 主循环: 接收并回显
main_loop:
    jal  ra, uart_getchar        # 阻塞等待读取一个字符，返回值在 a0
    mv   a1, a0                  # 将读到的字符保存到 a1
    jal  ra, uart_putchar        # 将字符回显输出
    j    pass               # 无限循环

#---------------------------------------------------------
# uart_putchar: 发送一个字符
# 参数: a0 = 待发送的字符
# 寄存器使用: 仅使用 t0, t1 (安全，不破坏 t2, t3)
#---------------------------------------------------------
uart_putchar:
    li   t0, UART_BASE + UART_LSR
wait_tx:
    lb   t1, 0(t0)               # 读取 LSR 寄存器
    andi t1, t1, 0x20            # 测试 THRE (Bit 5) 是否为 1
    beqz t1, wait_tx             # 如果为 0，继续等待

    li   t0, UART_BASE + UART_THR
    sb   a0, 0(t0)               # 将字符写入 THR
    ret                          # 直接返回

#---------------------------------------------------------
# uart_getchar: 接收一个字符
# 返回: a0 = 接收到的字符
# 寄存器使用: 仅使用 t0, t1 (安全，不破坏 t2, t3)
#---------------------------------------------------------
uart_getchar:
    li   t0, UART_BASE + UART_LSR
wait_rx:
    lb   t1, 0(t0)               # 读取 LSR 寄存器
    andi t1, t1, 0x01            # 测试 DR (Bit 0) 是否为 1
    beqz t1, wait_rx             # 如果为 0，继续等待

    li   t0, UART_BASE + UART_RBR
    lb   a0, 0(t0)               # 从 RBR 读取字符到 a0
    ret                          # 直接返回

#---------------------------------------------------------
# uart_puts: 输出以 0 结尾的字符串
# 参数: a0 = 字符串首地址
# 寄存器使用: t2 保存 ra, t3 保存字符串指针
# 注意: 内部调用了 uart_putchar，但 t2/t3 不会被破坏
#---------------------------------------------------------
uart_puts:
    mv   t2, ra                  # 1. 将返回地址安全保存到 t2
    mv   t3, a0                  # 2. 将字符串首地址安全保存到 t3
puts_loop:
    lb   a0, 0(t3)               # 3. 读取当前字符到 a0 (供 uart_putchar 使用)
    beqz a0, puts_end            # 4. 如果是 '\0'，结束打印
    jal  ra, uart_putchar        # 5. 输出字符 (uart_putchar 会修改 t0/t1，但不影响 t2/t3)
    addi t3, t3, 1               # 6. 字符串指针后移一个字节
    j    puts_loop               # 7. 继续循环
puts_end:
    mv   ra, t2                  # 8. 恢复返回地址到 ra
    ret                          # 9. 返回调用者

#----------------------------------------
.equ TOHOST_BASE, 0x0000000080001000
pass:
    li  t0, TOHOST_BASE
    li   t1, 1
    sw   t1, 0(t0)
    j    end

fail:
    li  t0, TOHOST_BASE
    li   t1, 2
    sw   t1, 0(t0)
    j    end

end:
    ebreak
#----------------------------------------

#---------------------------------------------------------
# 字符串数据直接放在代码段内
#---------------------------------------------------------
msg: .asciz "UART Test: "        # 测试提示字符串
