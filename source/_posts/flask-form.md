title: 实现一个简单优雅的Flask表单验证模块
date: 2016-08-22 22:40:43
categories:
- Programming
tags:
- Flask
- Python
---

## 背景

用Flask框架开发web应用的过程中，我们通常会在视图层写很多繁琐的代码来校验表单的数据，同时把提交的数据转换成业务需要的格式, 结果就是视图层的代码到处夹杂着表单验证的逻辑，显得错综复杂，难以维护。注意我所指的表单是更加广义的概念，包括query string或者通过Content-Type `application/json`传递的数据。先来来看一个样例:

```Python
from flask import request
@app.route('/register', methods=['POST'])
def register():
    username = request.form.get('username')
    if not username:
      raise ValueError('username cannot be empty')
    if len(username) > 10:
      raise ValueError('username should be less than 10')
    password = request.form.get('password')
    if not password:
      raise ValueError('password cannot be empty')
    if len(password) < 10:
      raise ValueError('username should be longer than 10')
    age = request.form.get('age')
    if not age:
      raise ValueError('age should not be empty')
    try:
      age = int(age)
    except (TypeError, ValueError):
      raise ValueError('age should be an integer')
    from_ = request.args.get('from')
    if from_ not in ('qq', 'weibo', 'native'):
      raise ValueError('invalid from')
    if from_ == 'weibo'
      register_weibo(username, password, age)
    if from_ == 'qq':
      register_qq(username, password, age)
    else:
      register_native(username, passowrd, age)
```

我们花费了大量的精力在获取和验证username, age, password和from_这几个字段， register的view层看上去就感觉很混乱，要改动某个字段的验证逻辑，还要在register函数 中找到对应这个字段的验证代码。有没有办法把表单验证的逻辑从视图层抽离出去，让视图层只做dispatch的活呢？

有django开发经验的同学会想那就来写个middleware吧，Flask其实也提供了middleware机制， 不过这个middleware是底层werkzeug库封装的wsgi中间件，不能很好地和flask框架的上下文结合起来。 其实我们完全可以从Python语言层面触发，利用Python强大的抽象能力，用最简单的方式解决问题。对， 你是不是也想到了，Python的万金油大杀器——decorator!

如果能在view函数上面套一个decorator就能把表单验证的活干了，view层的代码就会轻便很多。 我们试着设计一下这个decorator的API。

```python
from some_where import form
@app.route('/register', methods=['POST'])
@RegisterForm
def register():
   username = form.username
   password = form.passoword
   from_ = form.from
   age = form.age
   # register_logic...
```

我们希望通过声明式的方法来定义表单验证的逻辑

```Python
class RegisterForm:
    username = String('form', required=True, max_length=10)
    password = String('form', required=True, min_length=10)
    age = Int('form', required=True)
    from_ = String('args', required=True, enums=('qq', 'weibo', 'native'))
```

`form`和`args`分别表示从form和querystring获取数据。

如果我们能够实现`RegisterForm`, `String`, `Int`的功能, 让开发者只需要声明`RegisterForm`和对应的字段就能完成表单验证的工作, 那么视图层就能完全解脱出来，同时声明式的表单类也更容易维护。至少上面的register函数和RegisterForm已经非常赏心悦目了, 而且十分Pythonic。

Ok, 饼已经画好，现在我们来填坑吧, 整个实现的代码会用到一些比较高级的语言特性，比如descriptor和metaclass，建议读者先熟悉或温习一下相关内容。同时也会用到一些Python3 only的东西, 也许能够激发一下你对Python3的好奇心!


## Test first

虽然我不是TDD的忠实拥趸，但还是先来几个测试用例压压惊:

```python
import flask
import pytest

from forms import *

def test_form():
    app = flask.Flask(__name__)
    app.testing = True

    class BasicForm(Form):
        a = IntField('args', required=True, name='a')
        b = StringField('args', required=True)
        c = StringField('args', required=False, default='default')
        d = FloatField('args', required=True)

    class RequireForm(Form):
        x = StringField('args', required=True, default='default')

    @app.route('/')
    @BasicForm
    def index():
        assert form.a == 10
        assert form.b == 'hello'
        assert form.c == 'default'
        assert form.d == 12.5
        return ''

    with app.test_client() as c:
        c.get('/?a=10&b=hello&d=12.5')

    @app.route('/require')
    @RequireForm
    def require():
        return str(form.x)

    with app.test_client() as c:
        with pytest.raises(ValidationError):
            c.get('/require')

    class SizeForm(Form):
        s = IntField('args', min_val=5,max_val=10)

    @app.route('/size')
    @SizeForm
    def size():
        assert form.s == 5
        return ''

    with app.test_client() as c:
        c.get('/size?s=5')

    class ListForm(Form):
        l = CSVListField('args', each_field=IntField, description='list')

    @app.route('/list')
    @ListForm
    def list_form():
        assert form.l == [1, 2, 3]
        return ''

    with app.test_client() as c:
        c.get('/list?l=1,2,3')
```

实现了TDD大法的第一步<span style="color:red">red</span>，然后我们要做的就是想办法把他变<span style="color:green">绿</span>。

## 实现

需要实现的Form类是一个decorator，直接作用于view函数，那么结果肯定需要一个`callable`对象， 所以需要给Form类增加一个`__call__`方法。

```python
class Form:
    def __init__(self, view_func):
        self._view_func = view_func
        functools.update_wrapper(self, view_func)

    def __call__(self, *args, **kwargs):
        return self._view_func(*args, **kwargs)
```

Ok, 看上去好像什么也没做什么的。不过还记得之前的`from some_where import form`么，这个form对象又是什么东西？怎么可以直接import进来用了，它不是全局变量么？不，你似乎忘了有一个叫做 **threadl(greenlet)local** 的东西。Flask框架封装了threadlocal，提供了更加高级的API给开发者使用，比如`flask.request`就是一个threadlocal， 我们的form对象其实就是模拟了`flask.request`的机制。

```python
from flask.globals import _app_ctx_stack, _app_ctx_err_msg
from werkzeug.local import LocalProxy
def _lookup_current_form():
    top = _app_ctx_stack.top
    if top is None:
        raise RuntimeError(_app_ctx_err_msg)
    return getattr(top, 'form', None)


form = LocalProxy(_lookup_current_form)
class Form:
    def __call__(self, *args, **kwargs):
        _app_ctx_stack.top.form = self
        return self._view_func(*args, **kwargs)
```

在调用view函数之前先把Form实例丢到app context的栈顶，`form = LocalProxy(_lookup_current_form) `里的form是一个threadlocal的全局变量，因为每个请求只会提交一个表单，所以每个请求对应了一个threadlocal的form对象， 关于flask的app context和request context，希望读者自己去做一点功课，要把所有东西都讲一遍是在太累， 所以我是假设读者具备一定的基础， 这样交流起来比较轻松一点。

从暴露的API看到，`username`和`password`是全局form对象的属性，怎么才能在`form.username`的时候去从request里面拿到username的数据并做玩验证最后返回这个数据呢？显然，我们需要一个拦截机制来代理对username的访问，在Python里面，最直接的方法就是通过descriptor的`__get__`方法.
```Python
_none_value = object()

class FormField:
    VALID_SOURCES = ('args', 'form', 'json')

    def __init__(self, source='', *, name='', required=True,
                 default=None, description=''):
        if source and source not in self.VALID_SOURCES:
            raise ValueError('request source %s is not valid' % source)
        self.source = source or 'json'
        self.required = required
        self.default = default
        self.description = description
        self.name = name

    def __set__(self, instance, value):
        raise ValueError('form field attribute is readonly')

    def _get_request_data(self):
        if not hasattr(request, self.source):
            raise ValidationError(
                '%s is not a valid data source from request' % self.source)
        if self.source == 'json' and request.get_json(silent=True) is None:
            source = 'form'
        else:
            source = self.source
        req_data = getattr(request, source)
        # request.args or request.form
        if hasattr(req_data, 'getlist'):
            raw = req_data.getlist(self.name)
            if len(raw) == 1:
                return raw[0]
            if len(raw) == 0:
                return _none_value
            # 不支持多个值的表单字段, 请用csv代理
            raise ValidationError(
                'multi values form field %s is not to be supported!' % self.name)
        # request.json
        return req_data.get(self.name, _none_value)

    def __get__(self, instance, _):
        if instance is None:
            return self
        name = self.name
        data = self._get_request_data()

        if data is _none_value:
            if self.required:
                raise ValidationError('FIELD %s is required' % name)
            # return default directly
            self.__dict__[name] = self.default
            return self.default

        result = self.process(data)
        self.__dict__[name] = result
        return result

    def process(self, data):
        return data
```

FormField是一个BaseClass，注意到`__init__`方法的标签了么，`def __init__(self, source='', *, name=''...`中 '\*' 的意思是后面的参数必须是keyword的方式传进来，`FormField('args', name='username')` is Ok while `FormField('args', 'username')` is not. 这个Python3的新特性带来的好处是通过将某些参数设计成keyword only的形式，使API更加清晰明了，降低了调用方错误传参的可能性。 `__get___`方法拦截了对`FormField`实例的访问，`_get_request_data`解析request来获取原始数据， `_none_value`这个哨兵表示request中找不到对应字段。解析完request之后，需要调用`process`方法来对数据做校验和转化，子类通过override这个方法来实现自己的校验逻辑。 `self.__dict__[name] = result`这一步十分tricky， 通过把结果直接放到form对象的__dict__属性中，下次访问同名属性的时候就直接从`__dict__`中取出返回，而不需要在走一遍descriptor的`__get__`方法了。

下面是子类的实现
```python
class LengthLimitedField(FormField):
    def __init__(self, source='', *, min_length=None, max_length=None, **kwargs):
        self.min = min_length
        self.max = max_length
        super().__init__(source, **kwargs)

    def process(self, data):
        if self.max is not None and len(data) > self.max:
            raise ValidationError(
                'FIELD {} is limited to max length {} but actually is {}'.format(  # noqa
                    self.name, self.max, len(data)))
        if self.min is not None and len(data) < self.min:
            raise ValidationError(
                'FIELD {} is limited to min length {} but actually is {}'.format(  # noqa
                    self.name, self.min, len(data)))

        return super().process(data)


class SizedField(FormField):
    def __init__(self, source='', *, min_val=None, max_val=None,
                 inc_min=True, inc_max=True, **kwargs):
        self.min = min_val
        self.max = max_val
        self.inc_min = inc_min
        self.inc_max = inc_max
        super().__init__(source, **kwargs)

    def process(self, data):
        if self.max is not None:
            invalid = data > self.max if self.inc_max else data >= self.max
            if invalid:
                raise ValidationError(
                    'FIELD {} is limited to max value {} but actually is {}'.format(
                        self.name, self.max, data))
        if self.min is not None:
            invalid = data < self.min if self.inc_min else data <= self.min
            if invalid:
                raise ValidationError(
                    'FIELD {} is limited to min value {} but actually is {}'.format(
                        self.name, self.min, data))
        return super().process(data)


class TypedField(FormField):
    field_type = type(None)

    def process(self, data):
        try:
            data = self.field_type(data)
            return super().process(data)
        except (TypeError, ValueError):
            raise ValidationError(
                'FIELD {} cannot be converted to {}'.format(
                    self.name, self.field_type
                )
            )


class IntField(TypedField, SizedField):
    field_type = int


class FloatField(TypedField, SizedField):
    field_type = float


class BasicStringField(TypedField):
    field_type = str


class BoolField(TypedField):
    field_type = bool


class StringField(BasicStringField, LengthLimitedField):
    pass


class CSVListField(FormField):
    def __init__(self, source='', *, each_field, **kwargs):
        self.each_field = each_field
        super().__init__(source, **kwargs)

    def process(self, data):
        data_list = data.split(',')
        if isinstance(self.each_field, FormField):
            each_field = self.each_field
        else:
            each_field = self.each_field(source=self.source)
        return [each_field.process(elem) for elem in data_list]
```

上面提供了一些基本的字段类型, 拓展起来也很方便，只需要组合已有类型或者在新的类型中覆写`process`方法。 `super()`方法也是Python3 only的，我们看到`IntField`继承了TypedField和SizedField两个类，每个类的`process`方法都先做了自己的校验，然后丢给`super()`。那么TypedField和SizedField的process方法都会调用么，先调用哪一个呢？我们可以通过`IntField`的`__mro__`属性知道调用顺序。

    In [1]: IntField.__mro__
    Out[1]:
    (zeus.core.forms.IntField,
     zeus.core.forms.TypedField,
     zeus.core.forms.SizedField,
     zeus.core.forms.FormField,
     object)

所以调用顺序是`TypedField.process` -> `SizedField.process` -> `Form.process`。关于`mro`的机制，这里也不展开了。

还记得我们的API么，回顾一下Field的使用姿势

```python
class RegisterForm:
    username = StringField('form', required=True, max_length=10)
    password = StringField('form', required=True, min_length=10)
    age = IntField('form', required=True)
    from_ = StringField('args', required=True, enums=('qq', 'weibo', 'native'))
```

注意我们并没有把字段的name作为参数传入， 那么FormField又怎么知道字段的名字是什么呢? 又到了使用黑膜法的时候，虽然我一再承诺不率先使用metaclass。
```python
class FormFieldMeta(type):
    def __new__(cls, name, bases, attrs):
        for field, value in attrs.items():
            if isinstance(value, FormField):
                value.name = field
        return type.__new__(cls, name, bases, attrs)

class Form(metaclass=FormFieldMeta):
    def __init__(self, view_func):
        self._view_func = view_func
        functools.update_wrapper(self, view_func)
```
`FormFieldMeta`在`Form`类创建的时候，遍历了`Form`的属性，如果发现`FormField`就把对应的属性名设为`FormField`的name字段，所以千万别以为metaclass有多高深，其实是很简单的玩儿。（当然我假设你有了解过metaclass的原理）。

## 小结

Congrats! We'are done! 我们实现了一个声明式的基于decorator的flask表单验证模块。你可以试试现在再跑一下之前的测试用例。相关代码请参考[flask form](https://github.com/moonshadow/way-to-python-ninja/tree/master/advanced-flask/form)。 如果测试通过，接下来就可以走TDD的第三步——refactor了, enjoy yourself!。

回顾一下，为了实现这个模块，我们用到了decorator，descriptor， metaclass，keyword only argument, 多重继承，mro, flask的context global... 庆祝一下我们的成果吧！如果你对整个模块的实现都已经很清楚的理解了，恭喜你，You'are an Python veteran now. 如果你还有很多困惑，也不要着急，把每个点的功课一个一个做好，多动脑筋思考，相信最后肯定也能理解的。

Anyway, 如果你有更好的设计或者更加优雅的实现，不妨也拿出来分享一下。
