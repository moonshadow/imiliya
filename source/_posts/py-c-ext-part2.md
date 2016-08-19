title: An Introduction to Python C Extension Programming (Part2)
date: 2016-08-18 23:06:53
categories:
- Programming
tags:
- Python
- C
---

TL; DR.

## 什么是Python C Extension？

所谓[Python C Extension][c-ext]， 是指在CPython平台上面,遵循Python C Extension Interface写出来的c代码模块，经过编译后可以在Python代码中直接import，相当于一个Python Module。 通俗的讲，就是用C语言实现一个library，然后给这个library披一个Python模块的皮，好让Python程序像import其他普通Python模块一样来使用这个C library.

## 简单实现

我们直接看官方文档的例子来写一个extension 模块吧(偷个懒，这篇文章我就当官方文档的搬运工了)。

创建`main.py`:

```python
import spam

status = spam.system('ls -l')
```

spam是我们将要实现的Extension模块, 使用方式很简单，直接import就行了。

然后我们来实现这个模块。

<!-- more -->


创建`spam.c`:

```c
#include <Python.h>

static PyObject *SpamError;

static PyObject *spam_system(PyObject *self, PyObject *args) {
  const char *command;
  int sts;

  if (!PyArg_ParseTuple(args, "s", &command))
    return NULL;
   sts = system(command);
   if (sts < 0) {
    PyErr_SetString(SpamError, "System command failed");
    return NULL;
   }
   return PyLong_FromLong(sts);
};

static PyMethodDef SpamMethods[] = {
    {"system", spam_system, METH_VARARGS, "Execute a shell command."},
    {NULL, NULL, 0, NULL}
};


static struct PyModuleDef spammodule = {
    PyModuleDef_HEAD_INIT,
    "spam",
    "spam document",
    -1,
    SpamMethods
};

PyMODINIT_FUNC PyInit_spam(void) {
    PyObject *m;

    m = PyModule_Create(&spammodule);
    if (m == NULL)
        return NULL;

    SpamError = PyErr_NewException("spam.error", NULL, NULL);
    Py_INCREF(SpamError);
    PyModule_AddObject(m, "error", SpamError);
    return m;
};
```

WTF, 都是些什么鬼玩意儿?

`#include <Python.h>` 引入了Python C API的header文件，这样在`spam.c` 中就可以使用Python.h里面定义的结构， 函数和宏了，`Python.h`把`<stdio.h>, <string.h>, <errno.h>,<stdlib.h>`这些标准库的header都已经include了进来。 如果对Python.h里面的东西感兴趣, 在终端跑一下`python3-config --cflags`, 就能找到文件的位置。

    python3-config --cflags

在运行结果中找到header的路径(Mac)。

    -I/usr/local/Cellar/python3/3.5.2_1/Frameworks/Python.framework/Versions/3.5/include/python3.5m


直接cd到`/usr/local/Cellar/python3/3.5.2_1/Frameworks/Python.framework/Versions/3.5/include/python3.5m`目录就能找到这个header文件, Python源码的其他header文件也都在这里了。

`static PyObject *SpamError`定义了一个SpamError对象, 根据名字可以猜到这将是一个异常类。Python的所有对象对应的都是一个`PyObject`的结构， 你可以到object.h头文件里面看看PyObject是怎么定义的，不过只能看得一脸懵逼就是了，如果对Python源码好奇，墙裂推荐《Python源码剖析》这本书。 .

```
static PyObject *spam_system(PyObject *self, PyObject *args) {
  const char *command;
  int sts;

  if (!PyArg_ParseTuple(args, "s", &command))
    return NULL;
   sts = system(command);
   if (sts < 0) {
    PyErr_SetString(SpamError, "System command failed");
    return NULL;
   }
   return PyLong_FromLong(sts);
};
```

`spam_system`定义了一个静态函数。 `self`指向的是当前模块，`args`则是Python调用这个方法时传入的参数.
`PyArg_ParseTuple`把`args`解析成c字符串, 并让command指向这个字符串的地址， 然后调用std的system函数(通过include引入的)。 sts保存了系统调用的返回值，`sts < 0` 说明调用失败，通过`PyErr_SetString` 设置异常信息，否则`PyLong_FromLong`将返回值转换为Python 的int对象.

```
static PyMethodDef SpamMethods[] = {
    {"system", spam_system, METH_VARARGS, "Execute a shell command."},
    {NULL, NULL, 0, NULL}
};
```

SpamMethods是模块的成员方法列表，其实就是一个数组, 每个元素都是一个_PyMethodDef_的结果表示一个模块的一个成员方法. `system`是最后输出的变量名， spam_system是刚才定义的函数， _METH_VARARGS_表示Python调用这个函数是传参的方式。 `"Execute s shell command"` 是函数的注释信息. `{NULL, NULL, 0, NULL}` 起一个哨兵的作用，这样模块遍历_SpamMethods_到这里就知道所有成员都已经被定义了。

```c
static struct PyModuleDef spammodule = {
    PyModuleDef_HEAD_INIT,
    "spam",
    "spam document",
    -1,
    SpamMethods
};
```

定义了将要输出的模块对象, 这是一个`PyModuleDef`结构，spamMethods对应了上面定义的成员数组。 最后我们还需要定义模块的初始化方法:

```C
PyMODINIT_FUNC PyInit_spam(void) {
    PyObject *m;

    m = PyModule_Create(&spammodule);
    if (m == NULL)
        return NULL;

    SpamError = PyErr_NewException("spam.error", NULL, NULL);
    Py_INCREF(SpamError);
    PyModule_AddObject(m, "error", SpamError);
    return m;
};
```

`import spam` 的时候，Python C Extension的模块机制就会执行PyInt_spam函数来创建并初始化模块, 初始化过程中还会创建SpamError类并添加到spam模块的成员变量中, Py_INCREF增加一个SpamError的引用计数(后面会讲到Python 的reference counting).

至此spam模块的实现就算大功告成， 我们需要把他编译成可以直接import的模块. 手动编译设置各种参数比较麻烦，可以利用`distutils`里面的方法来构建.

创建setup.py

```
from distutils.core import setup, Extension

setup(name='sample', ext_modules=[
    Extension('spam', ['spam.c'])
])
```

注意Extension的`__init__`方法第一个参数指定了模块名为spam， 需要和模块初始化PyInit_spam中的spam保持一致， import spam的运行时，会根据这个参数的名字，去调用对应PyInit_name的方法。

运行

    python3 setup.py build_ext --inplace

会把spam.c编译成对应的dll模块，`inplace` 选项指定了结果文件的位置是当前目录.

跑一下我们的`main.py`

    python3 main.py

结果会在终端打印当前目录下的文件。

如果想安装到site-packages下面， 运行`python3 setup.py install`， 然后就可以在其他项目也能直接import spam模块了。

*Extension* 类的 *\_\_init\_\_* 方法还接受很多其他的参数: *include_dirs* 指定包含头文件的路径， *define_macros* 定义一些宏，*library_dirs* 指定动态链接的目录, 相当于gcc的 *-L* 选项，libraries 指定链接的库，相当与gcc的 *-l* 选项。还有其他一些参数读者请自行参考[distutils][distutils]。


## 错误和异常(Errors and Exception)

Python解释器有一个不成文的规定， 当函数失败的时候，需要设置一个异常信息，并且返回错误值，异常信息保存在解释器的一个静态全局变量中。如果这个变量的值为NULL(空指针)，说明没有异常发生。除此之外还有两个全局变量，一个保存了异常信息对应的描述，另一个保存了发生异常时的整个调用堆栈, 它们对应了sys.exc_info()结果的三个元素。

前面用到的PyErr_SetString()方法，第一个参数就是我们定义的异常类对象,第二个参数是关联的异常信息描述。 *PyErr_SetString(SpamError, "System command failed")* 设置了全局的异常信息,Python解释器发现这个异常信息的时候，会跳转到异常处理流程(如果想了解Python解释器是怎么运作的, 异常机制又是如何实现的，再次推荐《Python源码剖析》这本书)。

## 一点题外话——引用计数(Reference Counts)

C和C++要求程序员负责动态的分配和回收堆上的内存，C语言提供了malloc()和free()函数(C++对应有new和delete操作符)。

每一个malloc()分配的内存资源， 最终都需要通过调用free()来回收, 如果忘记了free， 被分配的内存资源直到进程退出都无法重新利用，这就是所谓的内存泄漏(memory leak)。如果继续使用free()过的内存， 很有可能和以后通过malloc()重新分配的内存资源冲突，会造成同引用没有初始化的指针一样的结果，core dumps, 错误的结果，进程莫名崩溃之类。

常见的内存泄露都是程序忘记调用free造成的，比如错误处理的逻辑中直接return却没有free之前分配的内存，尤其是代码量比较大的时候很容易出现。如果某个有内存泄露的函数被大量的调用，那么每次调用都会造成一定的内存泄漏, 如果只是短暂运行的进程，随着进程结束，这些资源都会被操作系统回收。但是如果是长时间运行的进程（比如一个后台daemon)，没有回收的内存资源会随着程序运行时间的增加而增加，最终把系统资源耗尽，程序崩溃。 所以通过一个好的编码规范避免内存泄露就显得十分重要。

Python大量的使用了malloc和free来管理内存，就必须有一个好的策略来避免上面提到的问题。Python使用的主要方法是 _reference counting_(引用计数) . 简单地讲， 每一个对象都有一个引用计数器，每当有新的引用，计数器的值+1, 如果引用被删除，计数器的值就-1，当计数器的值减到0，这个对象占用的内存就可以回收了。

引用计数不能解决循环引用的问题，循环引用是指存在互相引用的对象，引用计数永远不可能减到0, 我们来看一个粗暴的例子:

```python
import gc
gc.disable() # 关闭gc功能
while True:
  a = [1] * 1000000
  b = [1] * 1000000
  a.append(b)
  b.append(a)
  del a
  del b
```

**友情提示**  千万不要手贱运行上面的代码!! 对于不听劝告的小朋友，如果造成无法挽回的后果本人表示不负任何责任。

`del a`和`del b`后，我们的程序已经没有对这两个对象的引用了，但是b和a还是互相引用了对象，他们的refcount都是1，那么引用计数机制就永远不会去回收a和b的内存, 每个While循环都会出现一次循环引用，这个程序会迅速蚕食掉你的内存。


 Python通过一个叫做[cycle detector](https://en.wikipedia.org/wiki/Cycle_detection)的技术解决了这个问题，[gc](https://docs.python.org/3/library/gc.html#module-gc)模块甚至提供了collect方法让程序员自己手动处理循环引用。如果你能保证你的Python代码不会出现循环引用的情况，可以通过`--without-cycle-gc`这个启动选项关掉自动回收的功能, 不过不建议这么做，Why bothering your self if Python could handle it for you?

也许你可以试试把上面的`gc.disable()`这一行注释掉再运行这段代码。  Please be very very careful!


Python通过引用计数和垃圾回收，实现了内存的自动管理，把Python程序员从手动内存管理的负担重解脱了出来，下面我们来看看Python的引用计数是具体是怎么玩的。

### Reference Counting in Python

Note:  下面提到`ref`, `reference`, `引用`这三个词没有什么区别。

Python通过两个宏 Py_INCREF(x) and Py_DECREF(x)来操作对象的引用计数。问题是这两个宏都需要在什么时候去调用呢？


Python的API文档中介绍了几个术语。

* **own**: 一个对象有很多个reference，每个reference对应会有一个owner， 一个对象的引用计数就是owner的个数. owner可以通过传递， 保存，或者直接Py_DECREF()来放弃对这个对象的reference。

* **borrow**:  并不own一个reference，不会增加对象的引用计数，因此也不需要调用Py_DECREF, 如果对一个borrow的reference调用了Py_INCREF， 就把他变成了一个owner。

当一个对象的引用作为参数传入函数或者作为函数的返回结果时， 根据函数的接口定义，我们可以知道对应ownership有没有被转移。

大多数返回一个引用的函数会把ownership交给调用者， 一般的如果函数创建了新的对象并返回对这个对象的引用，比如PyLong_FromLong(), Py_BuildValue, 那么这个引用的ownership转给了调用者。例外的是 PyTuple_GetItem(), PyList_GetItem(), PyDict_GetItem(), and PyDict_GetItemString()这些函数，只是返回一个borrowed引用。

当对象引用作为参数传入函数的时候，一般情况下函数都是borrow了这个reference，并不增加引用计数，如果函数需要增加引用计数，需要显示调用Py_INCREF。 不过也有例外， PyTuple_SetItem() and PyList_SetItem()这两个函数就接管了引用成为owner。

是不是感觉很抽象(反正我刚开始的时候就是一脸懵逼), 为什么一会儿要borrow一会儿要own的...下面举几个例子来分析一下你应该就能稍微明白一点了.

```c
void
bug(PyObject *list)
{
    PyObject *item = PyList_GetItem(list, 0);

    PyList_SetItem(list, 1, PyLong_FromLong(0L));
    PyObject_Print(item, stdout, 0); /* BUG! */
}
```

PyList_GetItem返回了list第一个元素的引用，根据[PyList_GetItem](https://docs.python.org/3.5/c-api/list.html#c.PyList_GetItem)的文档我们知道这个函数返回的是一个borrowed引用, 也就是说不会增加list[0]这个元素的引用计数（我们假设现在list[0],list[1]的refcount都是1), 接下来我们设置list[1]元素的值为0(新创建的int对象)，而原先的list[1]引用的对象的refcount就会减1变成0，这个时候 原先list[1]对象的[`__del__`](https://docs.python.org/3/reference/datamodel.html#object.__del__)就会被调用，而`__del__`方法可以直接访问list[0]的元素，如果在里面调用del list[0], list[0]元素的引用计数也减为0了，PyObject_Print函数就会访问到一个已经被回收的内存地址, 下面是模拟这个场景的python代码。
```python

list0 = object()

class Obj:
    def __del__(self):
      del list0

list1 = Obj()
l = [list0, list1]
```
所以如果是borrow一个引用的话，必须保证在使用这个引用的过程中这个引用对象的refcount不会减为0, 修改前面的C代码。

```C
void
no_bug(PyObject *list)
{
    PyObject *item = PyList_GetItem(list, 0);

    Py_INCREF(item);
    PyList_SetItem(list, 1, PyLong_FromLong(0L));
    PyObject_Print(item, stdout, 0);
    Py_DECREF(item);
}
```

在PyList_SetItem之前增加item对象引用计数，保证了PyObject_Print访问到的item的有效性。

或者使用[PySequence_GetItem](https://docs.python.org/3.5/c-api/sequence.html#c.PySequence_GetItem)方法，查看文档我们发现这个函数返回的是一个owner reference，增加了一个对对应元素对象的引用计数。

```C
void
no_bug(PyObject *list)
{
    PyObject *item = PySequence_GetItem(list, 0);
    PyList_SetItem(list, 1, PyLong_FromLong(0L));
    PyObject_Print(item, stdout, 0);
    Py_DECREF(item);
}
```

只需要用完之后调用Py_DECREF来去掉刚才增加的引用计数, 但是值得注意的是PySequence_GetItem既然返回的是一个owner, 那么用这个它的目的就是要长时间占用的，而不是像上面这样只是print一下, 这个地方用PySequence_GetItem其实已经失去本意了, 用PyList_GetItem暂时borrow一下是更加正确的选择。

所以你发现borrow和own的区别了么? borrow过来reference的不会占用一个计数，在使用borrow的引用过程中必须要自己保证引用有效，如果可以保证中间没有操作可能减少这个引用计数的话，我们甚至省去了INC和DEC引用的烦恼，所谓borrow就是我借过来用一下，等下肯定会还你的。这个比喻其实有一点不恰当的地方，因为borrow的reference其实也被借出方占着的，比如上面的list也还是可以访问item对象，借的过程中借用方甚至还要担心被借走的东西被已经被处理掉的可能（PyList_SetItem）， 这其实就不叫借了吧，还不如说是暂时share给你一会儿，虽然你也能用，但是别人问起来你得说这个东西你并没有所有权, 而且share给你的人心情不好把东西给卖了你就用不了了，这个时候Py_INCREF就好像在说你先别卖啊，我还没用完呢，Py_DECREF则是说我现在已经不用了，你爱怎么玩怎么玩。own就不一样了，如果我们两个都own了一个东西，那么光你说卖还不成，你只能说自己不要了（像del list0)那样，但是我还占着一份呢，Py_DECREF则是说现在我也不想要了——喂，那个捡垃圾的(item的 `__del__` 方法)，你来拿走吧。 不知道这样表述清不清楚。


对于上面的例子，Python的GIL保证了这个函数调用过程不会被其他线程打断,因此我们不必担心被borrow的引用item在另一个线程被回收了（比如在另一个thread调用了PyList_SetItem，里面又做了减少item引用计数的事情（论GIL的重要性). 但是python提供了Py_BEGIN_ALLOW_THREADS这个宏来暂时解除全局锁，看看下面的这个代码

```c
void
bug(PyObject *list)
{
    PyObject *item = PyList_GetItem(list, 0);
    Py_BEGIN_ALLOW_THREADS
    ...some blocking I/O call...
    Py_END_ALLOW_THREADS
    PyObject_Print(item, stdout, 0); /* BUG! */
}
```

Py_BEGIN_ALLOW_THREADS和Py_END_ALLOW_THREADS之间，GIL被释放了，于是item就有可能在另一个线程被回收掉，后面在执行 PyObject_Print就可能产生意想不到的bug!

用borrow还是own其实并没有明确的规定，取决于那个模型在特定场景下使用更加方便，我们可以通过官方文档知道某个Python C API的函数具体用的borrow还是own。


讲了这么多引用计数的东西好像已经偏题了, 看得出来在C Extension里面对引用计数的处理也是一件比较tricky的事情。如果你对这块很感兴趣，直接阅读[官方文档](https://docs.python.org/3/extending/extending.html)是一个不错的选择, 这篇文章[http://edcjones.tripod.com/refcount.html](http://edcjones.tripod.com/refcount.html)则做了一定的解释和补充。 please keep reading patiently!

如果你对 *borrow*，*own* 这一块很感兴趣 ,隔壁有一门叫做[Rust](https://doc.rust-lang.org)的语言值得尝试, 可以看看它的 *ownership system* 是怎么玩的。

## 总结

简单的讲, 实现一个C Extension模块要做好三件事情

1. 满足C Extension接口的规范
2. 处理好数据在Python和C之间的转化
3. 用C语言实现具体的功能（或者调用已有的库)

再回顾一下我们的spam.c文件，所有变量的定义都是static的，表示这些变量的作用域仅限于`spam.c`，起到了限制作用域的作用。

```C
SpamError = PyErr_NewException("spam.error", NULL, NULL);
Py_INCREF(SpamError);
PyModule_AddObject(m, "error", SpamError);
```
因为[PyModule_AddObject](https://docs.python.org/3.5/c-api/module.html#c.PyModule_AddObject)不会增加SpamError的引用计数,官方的话叫steal the reference, 如果我们不手动INC一下，那么以后删除了m.error这个属性的话，SpamError的计数就变0，对应的内存被回收，如果后面又抛出了这个异常救护出现意想不到的错误。

PyArg_ParseTuple的format参数格式请参考[PyArg_ParseTuple][py-arg], 与之对应的还有`Py_BuildValue` 函数， 用来构造Python对象.

[相关代码](https://github.com/moonshadow/way-to-python-ninja/tree/master/python-c-ext/impl-python-c-ext)

Anyway, 手动实现一个Python C Extension始终是一件很麻烦的事(还要了解Python的引用计数是怎么玩的)。如果只是简单系统调用，用`ctypes`就能直接搞定， 那专心写好C代码，然后直接让Python像用普通模块一样把它用起来岂不是更加方便？ 下一篇我们就来看看一个叫做CFFI的第三方库又是怎么实现在Python中调用C语言库的吧。

[c-ext]: https://docs.python.org/3/extending/extending.html
[py-arg]: https://docs.python.org/3/c-api/arg.html
[distutils]: https://docs.python.org/3.5/distutils/apiref.html#distutils.core.Extension
