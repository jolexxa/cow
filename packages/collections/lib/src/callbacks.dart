/// A callback that takes no arguments and returns nothing.
typedef VoidCallback = void Function();

/// A callback that receives a non-null [Object].
typedef ObjCallback = void Function(Object);

/// A callback that receives a nullable [Object].
typedef ObjCallbackNullable = void Function(Object?);

/// A callback that receives a value of type [TValue].
typedef ValueCallback<TValue> = void Function(TValue);

/// A callback that takes no arguments and returns a value of type [TReturn].
typedef FuncCallback<TReturn> = TReturn Function();

/// A callback that receives a value of type [TValue] and returns a value of
/// type [TReturn].
typedef Func1Callback<TValue, TReturn> = TReturn Function(TValue);

/// A callback that receives values of type [TValue1] and [TValue2] and returns
/// a value of type [TReturn].
typedef Func2Callback<TValue1, TValue2, TReturn> = TReturn Function(
  TValue1,
  TValue2,
);
