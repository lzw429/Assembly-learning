# lesson5 设置最初的页表，进行系统初始化
# head.s程序在被编译生成目标文件后会与内核同其他程序一起被链接为system
# 模块，位于system模块的最前面开始部分。因此这段程序被称为head。

# head.s含有32位启动代码
# 32位启动代码是从绝对地址0x00000000开始的，这里也同样是页目录将存在的
# 地址，因此这里的启动代码将被页目录覆盖。

.text
.global idt, gdt, pg_dir, _tmp_floppy_area   # pg_dir即页目录    
pg_dir: # 页目录将会存放在这里
.global startup_32

# 这里已经处于32位运行模式，因此这里的$0x10并不是把地址0x10装入各个段寄
# 存器，其实是全局段描述符表GDT中的偏移值，更准确地说是一个描述符表项的
# 选择符。$0x10的含义是请求特权级0（位0-1=0）、选择全局描述符表（位2=0）
# 选择表中第2项（位3-15=2）。它正好指向表中的数据段描述符项。
startup_32:                                 #设置各个数据段寄存器
    movl $0x10, %eax                        # movl是32位指令
    mov %ax, %ds
	mov %ax, %es
	mov %ax, %fs
	mov %ax, %gs
    lss stack_start, %esp                   # 将stack_start指向ss:esp，设置系统堆栈
                                            # stack_start定义在kernel/sched.c
    call setup_idt                          # 调用设置中断描述符表子程序
    call setup_gdt                          # 调用设置全局描述符表子程序
    mov $0x10, %eax                         # 因为修改了GDT，所以需要重新装载所有的段寄存器
  	mov %ax, %ds                            # CS代码段寄存器已经在setup_gdt中重新加载过了
	mov %ax, %es
	mov %ax, %fs
	mov %ax, %gs

    lss stack_start, %esp                   # 确保CS被重新加载

# 下面测试A20地址线是否已经开启，采用的方法是向内存地址0x000000处写入任意
# 一个数值，然后看内存地址0x100000（1MB）处是否也是这个数值。如果一直相同
# 的话，就一直比较，即死循环、死机。表示地址A20线没有选通，结果内核就不能
# 使用1MB以上内存。

# 下面的‘1:’是一个局部符号构成的标号。标号由符号后跟一个冒号组成。此时该
# 符号表示活动位置计数的当前值，并可以作为指令的操作数。局部符号用于帮助
# 编译器和编程人员临时使用一些名称。共有10个局部符号名，可在整个程序中重
# 复使用。这些符号名使用名称‘0’、‘1’、……、‘9’来引用。为了定义一个局部符
# 号，需把标号写成‘N:’形式（其中N表示一个数字）。为了引用先前最近定义的
# 这个符号，需要写成‘Nb’，其中N是定义标号时使用的数字。为了引用一个局部
# 标号的下一个定义，需要写成‘Nf’，这里N是10个前向引用之一。上面的‘b’表
# 示backwards，f表示forwards。在汇编程序的某一处，我们最大可以向前/向
# 后引用10个标号。

    xorl %eax, %eax
1:  incl %eax
    movl %eax, 0x000000
    cmpl %eax, 0x100000
    je 1b                                   # 如果一直相同就一直比较

# 下面检查486数学协处理器是否存在。方法是修改控制寄存器CR0，在假设存在
# 处理器的情况下执行一个协处理器指令，如果出错的话则说明协处理器芯片不
# 存在，需要设置CR0中的协处理器仿真位EM（位2），并复位协处理器存在标志
# MP（位1）。
    movl %cr0, %eax                         # 检查数学协处理器
    andl $0x80000011, %eax                  # 保存PG，PE，ET
    orl $2, %eax                            # 设定协处理器存在标志MP
    movl %eax, %cr0
	call check_x87
	jmp after_page_tables

check_x87:
    fninit                                  # 向协处理器发出初始化命令
    fstsw %ax                               # 取协处理器状态字到ax寄存器中
    cmpb $0, %al                            # 初始化后状态字应该为0，否则协处理器不存在
    je 1f
   	movl %cr0, %eax                         # 如果存在则向前跳转到标号1，否则改写cr0。
	xorl $6, %eax                           # 重置协处理器仿真位MP，设定协处理器存在标志EM
	movl %eax, %cr0
	ret

# 下面是一汇编语言指示符。其含义是指存储边界对齐调整。“2”表示把随后的
# 代码或数据的偏移位置调整到地址值最后2比特位为零的位置，即按4字节方式
# 对齐内存地址。
.align 2
1:
    .byte 0xDB, 0xE4                        # 287协处理器码
    ret

# 下面这段是设置中断描述符表子程序 setup_idt
# 将中断描述符表IDT设置成具有256个项，并都指向ignore_int中断门。然后
# 加载中断描述符表寄存器（用lidt指令）。真正实用的中断门以后再安装。
# 当我们在其他地方认为一切都正常时再开启中断。该子程序将会被页表覆盖掉。
setup_idt:
    lea ignore_int, %edx                    # 将ignore_int的有效地址（偏移值）赋给edx
    movl $0x00080000, %eax                  # 将选择符0x0008置于eax的高16位中。
    movw %dx, %ax                           # 偏移值的低16位置入eax的低16位中。
                                            # 此时eax含有门描述符低4字节的值。
    mov $0x8E00, %dx                        # 此时edx含有门描述符高4字节的值。
    lea idt, %edi                          # _idt是中断描述符表的地址。
    mov $256, %cx

rp_sidt:
	mov %eax, (%edi)                        # 将中断门描述符存入表中。
	mov %edx, 4(%edi)                       # eax内容放到edi+4所指内存位置处。
	addl $8, %edi                           # edi指向表中下一项。
	dec %cx
	jne rp_sidt
	lidt idt_descr			                # 加载中断描述符表寄存器值。

setup_gdt:
    lgdt gdt_descr
    ret

# Linus将内核的内存页表直接放在页目录之后，使用了4个表来寻址16MB的物理内存。
.org 0x1000    # 从偏移0x1000处开始是第1个页表（偏移0开始处将存放页表目录）
pg0:

.org 0x2000
pg1:

.org 0x3000
pg2:

.org 0x4000
pg3:

.org 0x5000                          # 定义下面的内存数据块从偏移0x5000处开始

# 当DMA（直接存储器访问）不能访问缓存块时，下面的_tmp_floppy_area内存块就可供
# 软盘驱动程序使用。其地址需要对齐调整，这样就不会跨越64KB边界。
_tmp_floppy_area:
    .fill 1024, 1, 0                 # 共保留1024项，每项1字节，填充数值0。

# 下面数个入栈操作用于为跳转到init/main.c中的main()函数作准备工作。
after_page_tables:
    push $0                         # 0表示envp的值 
	push $0                         # 0表示argv的值
	push $0                         # 0表示argc的值
	pushl $L6                       # 在栈中压入返回地址
	pushl $main                     # 将main.c的地址压入堆栈
	jmp setup_paging                # 分页处理结束后，执行ret后就会执行main.c
L6:
	jmp L6                          # main程序绝对不应该返回到这里，此处为了以防万一。

int_msg:
    .asciz "Unknown interrupt\n\r"  # 定义字符串“未知中断（回车换行）”

.align 2                            # 按4字节方式对齐内存地址
ignore_int:
    pushl %eax
	pushl %ecx
	pushl %edx
	push %ds                        # ds，es，fs，gs虽然是16位寄存器，但仍以32位形式入栈
	push %es
	push %fs
	movl $0x10, %eax                # 置段选择符（使ds，es，fs指向gdt表中的数据段）
	mov %ax, %ds
	mov %ax, %es
	mov %ax, %fs
	pushl $int_msg                  # 把调用printk函数的参数指针入栈。
    # 若符号int_msg前不加$，则表示把int_msg符号处的长字‘Unkn’入栈。
	call printk                    # 该函数在/kernel/printk.c中。
	popl %eax
	pop %fs
	pop %es
	pop %ds
	popl %edx
	popl %ecx
	popl %eax
	iret                            # 中断返回（把中断调用时压入栈的32位CPU标志寄存器也弹出）

# 这个子程序通过设置控制寄存器cr0的标志（PG位31）来启动对内存的分页处理功能，
# 并设置每个页表项的内容，以恒等映射前16MB的物理内存。分页器假定不会产生非法
# 的地址映射，即在只有4Mb的机器上设置出大于4Mb的内存地址。
# 机器物理内存中大于1MB的内存空间主要被用于主内存区。主内存区空间由mm模块管理。
# 它涉及到页面映射操作。内核中所有其他函数就是这里指的一般函数，若要使用主内存区
# 的页面，就需要使用get_free_page()等函数获取。因为主内存区中内存页面是共享资源，
# 必须有程序进行统一管理以避免资源争用和竞争。
.align 2							# 按4字节方式对齐内存地址边界
setup_paging:						# 首先对5页内存（1页目录+4页地址）清零
	movl $1024 * 5, %ecx			
	xorl %eax, %eax
	xorl %edi, %edi					# 页目录从0x000地址开始
	cld;rep;stosl					# eax内容存到es:edi所指内存位置处，且edi增4。

# 下面4句设置页目录表中的项，因为内核共有4个页表所以只需设置4项。
# 页目录项的结构与页表中项的结构一样，4个字节为1项。
	movl $pg0+7, pg_dir
	movl $pg1+7, pg_dir+4
	movl $pg2+7, pg_dir+8
	movl $pg3+7, pg_dir+12

# 下面填写4个页表中所有项的内容，共有4页表*1024项/页表=4096项。
# 也即能映射物理内存4096*4Kb=16Mb。
# 每项的内容是：当前项所映射的物理内存地址+该页的标志（这里均为7）
# 使用的方法是从最后一个页表的最后一项开始按倒退顺序填写。
	movl $pg3+4092, %edi
	movl $0xfff007, %eax

	std								# 方向位置位，edi值递减（4字节）
1: 	stosl							
	subl $0x1000, %eax				# 每填写好一项，物理地址值减0x1000。
	jge 1b							# 如果小于0则说明全填写好了

# 设置页目录表基址寄存器cr3的值，指向页目录表。cr3中保存的是页目录表的物理地址。
	xorl %eax, %eax					# 页目录表在0x0000处。
	movl %eax, %cr3
# 设置启动使用分页处理（cr0的PG标志，位31）
	movl %cr0, %eax
	orl $0x80000000, %eax			# 添上PG标志。
	movl %eax, %cr0
	ret

# 在改变分页处理标志后要求使用转移指令刷新预取指令队列，这里用返回指令ret。
# 该返回指令的另一个作用是将压入堆栈的main程序的地址弹出，并跳转到/init/
# main.c程序去运行。本程序到此就真正结束了。
.align 2							# 按4字节方式对齐内存地址边界。
.word 0								# 这里先空出2字节，确保后面.long长字是4字节对齐的

# 下面是加载中断描述符表寄存器idtr的指令lidt要求的6字节操作数。前2字节是IDT表的限长，
# 后4字节是IDT表在线性地址空间中的32位基地址。
idt_descr:
	.word 256 * 8 - 1				# 共256项，限长 = 长度-1.
	.long idt

.align 2
.word 0

# 下面加载全局描述符表寄存器gdtr的指令lgdt要求的6字节操作数。前2字节是gdt表的限长，
# 后4字节是gdt表的线性基地址。这里全局表长度设置为2KB字节，因为每8字节组成一个描述
# 符项，所以表中共可有256项。符号_gdt是全局表在本程序中的偏移位置。
gdt_descr:
	.word 256 * 8 - 1
	.long gdt
	.align 8						# 按8（2^3）字节方式对齐内存地址边界。

idt:
	.fill 256,8,0					# 256项，每项8字节，填0.

# 全局表。前4项分别是空项（不用）、代码段描述符、数据段描述符、系统调用段描述符，
# 其中系统调用段描述符并没有用处。
gdt:
	.quad 0x0000000000000000
	.quad 0x00c09a0000000fff		# 0x08，内核代码段最大长度16MB。
	.quad 0x00c0920000000fff		# 0x10，内核数据段最大长度16MB。
	.quad 0x0000000000000000
	.fill 252, 8, 0					# 预留空间
