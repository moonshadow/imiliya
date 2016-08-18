title: An Introduction to Python C Extension Programming (Part1)
date: 2016-08-16 06:45:36
categories:
- Programming
tags:
- Python
- C
---

## 写博客的动机

当了这么久的程序员，中间有好几次也想过开个博客写点什么。可是一来觉得自己太菜，再又实在过于怠惰，计划就搁置一旁(买了个域名躺了一年😂)。 然而一直以来看了各路大侠的博客，偷偷学到不少东西, 感觉好像也没那么菜了，也觉着应该把自己的一些想法和见解分享出去，回馈社会, 而不是在自己的脑子里面憋着， 即使被打脸也算是又学到了嘛, 何乐而不为。

在下一介Python程序员, 而且是*真のPython粉*，那就从Python写起吧, 也比较得心应手一点。现今市面上充斥各种Python教程(Python也真是太简单易上手了), 我就不去凑这个热闹也讲些Python基础或者*tips*什么的了。将要讲到的内容都是面向至少中级的Python程序员的. 所以读者最好是具备一定的Python水平，如果是刚入门的小朋友, 至少先买两本入门教程撸一遍再来吧，请点击右上角不送。

暂定的系列有

1. Python C Extension
1. Profile
1. Debugging
1. Python2 or Python3
1. Unicode
1. AsyncIO
1. Modules
1. Logging

## First of first (Python C Extension)

不知道大家觉得Python最神秘的地方在哪里。反正在我的经验看来，最搞不清扯不明的地方就是所谓的Python C Extension Module了。ctypes， cffi， swig， cython, numba这些名词，听上去就觉得好可怕, 想搜个像样子的介绍文章出来都难, 直接看官方文档吧有感觉有点overwhelming. 所以我希望通过C Extension这个系列的文章，把这些玩意儿一个一个都探索一下。 本人C语言水平有限，如果有胡说八道的地方， 欢迎指正，大家一起学习进步😀。 以后所有文章只针对Python3，关于*Python2 or Python3*, 以后也会找机会讨论一下, 如果有必要联系Python2的相关知识我会专门指出, 文中所有涉及到编译c代码的地方都假设读者使用的是类unix的操作系统(原因是我对windows的生态系统实在一无所知)。

## why C?

好吧，我们用Python是因为它很高的抽象层次，可以帮助我们迅速的构建应用，不论是写一个简单的任务脚本还是搭一个小型网站，Python都是上佳选择。然而世上没有免费午餐，开发效率的代价是牺牲了软件性能，不过一般情况下这都不是事，比如Python构建的web app性能瓶颈大多都在IO，这是没法在代码层面优化的, 可以通过改变IO模型或者扩容服务器来解决。而且一般的Python程序员习惯了Python的简介优雅，可能对性能什么的没什么概念。不过夜路走多了总会撞鬼，平常没有意识，真正性能出现问题需要优化的时候只能是一脸懵逼。如果能够具备一定的性能意识，在需要的时候知道有哪些办法可以选择和尝试，那么至少是走在了正确的道路上。性能Profile也是一个大的话题，以后再展开。

学习C Extension Programming也能加深对Python语言本身的理解， 对于写出更高质量的Python代码也是很有帮助的。 所以废话不多说，进入第一个话题，如何在Python代码里面调用C函数.

## How to call C function in Python code?

python标准库提供了[**ctypes**][ctypes]模块, 可以帮助我们把DLL或者shared libraries(共享库)中的函数封装成可以直接调用的Python函数。如果发现需要的某个工具已经有C语言的library, 我们就不需要重新用Python实现相同功能的模块， 既保证了效率还能省去性能的烦恼。下面是一个简单的例子:

首先我们创建一个C文件`utils.c`, 定义factorial和swap两个函数.

```c
int factorial(int x) {
  if (x <= 0) {
    return 1;
  }
  return factorial(x-1) * x;
}

void swap(int *a, int *b) {
  int temp = *a;
  *a = *b;
  *b = temp;
}

```

然后编译成目标文件`utils.o`(我用的是Mac下面的LLVM编译器）

```bash
gcc -c -Wall -Werror utils.c
```

再把刚生成的目标文件转化成动态链接库.

```
gcc -shared -o libutils.so utils.o
```

我们需要做的就是在*Python*代码中调用刚才在`utils.c`中定义的两个函数. 下面示例如何用*ctypes*来操作，创建文件`main.py`:

```python
import ctypes


utils = ctypes.cdll.LoadLibrary('./libutils.so')

factorial = utils.factorial
factorial.argtypes = (ctypes.c_int,)
factorial.restype = ctypes.c_int

_swap  = utils.swap
_swap.argtypes = (ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int))


def swap(x, y):
    a = ctypes.c_int(x)
    b = ctypes.c_int(y)
    _swap(a, b)
    return a.value, b.value


if __name__ == "__main__":
    print('factorial of 4 is %s !' % factorial(4))
    print('factorial of 5 is %s !' % factorial(5))

    x, y = 10, 20
    print('x is %s and y is %s' % (x, y))
    x, y = swap(x, y)
    print('after swap')
    print('x is %s and y is %s' % (x, y))
```

`utils = ctypes.cdll.LoadLibrary('./libutils.so')` 载入了已经编译好的`libutils.so`, factorial和swap两个函数变成了模块的locals.（如果不是自己编译的模块而是想用系统的C语言共享库，参考`cypes.utils`的`find_library`方法，路径通常都是`/usr/lib` 和 `/usr/local/lib`， linux操作系统默认都是*libxxx.so*的格式， 而os x则是*libxxx.dylib*)

对于`factorial`函数，只需要把python的int对象转换成对应的ctype类型再传入factorial函数， 同时需要定义返回的结果类型，把factorial函数返回的int转换成Python的int对象

`swap`函数稍微麻烦一点，因为Python不能直接访问指针，所以需要把已有的c函数稍微做个封装， 不过思路一样就是了.

最后验证一下结果。
运行

    python3 main.py

终端输出

    factorial of 4 is 24 !
    factorial of 5 is 120 !
    x is 10 and y is 20
    after swap
    x is 20 and y is 10

Perfect! 简单的几个步骤，我们就实现了在Python中调用c函数.

顺便我们对比一下C语言实现的factorial和Python版本的性能,

```python
import ctypes
from timeit import timeit


utils = ctypes.cdll.LoadLibrary('./libutils.so')

factorial = utils.factorial
factorial.argtypes = (ctypes.c_int,)
factorial.restype = ctypes.c_int

def py_factorial(n):
    assert isinstance(n, int)
    if n <= 0:
        return 1
    return py_factorial(n-1) * n

if __name__ == "__main__":
    number = 100000
    print('Python 版本100000次的factorial(10)时间')
    print(timeit('py_factorial(10)', number=number, globals=globals()))
    print('C 版本100000次的factorial(10)时间')
    print(timeit('factorial(10)', number=number, globals=globals()))
```

保存到`benchmark.py`

在我的机器上运行的结果是

    Python 版本100000次的factorial(10)时间
    0.3275668309943285
    C 版本100000次的factorial(10)时间
    0.07990392099600285

大概4倍的样子, very nice!

第一个例子就到这里了，ctypes打开了Python调用c代码库的大门。 然而很多时候并没有现成的c库给我们调， 那么就需要自己写Python的C Extension了，下一篇我们先研究一下如何裸写一个Python的C extension模块吧.

上面示例的代码已经放到[**github**][way-to-python-ninja]上面了，可以拉下来参照[**ctypes**][ctypes]的文档自己玩玩, 如果你有更好的sample或者建议欢迎一起交流.


[ctypes]: https://docs.python.org/3.5/library/ctypes.html#module-ctypes
[way-to-python-ninja]: https://github.com/moonshadow/way-to-python-ninja
