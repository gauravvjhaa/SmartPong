# Keep TensorFlow Lite classes
-keep class org.tensorflow.** { *; }
-keep class org.tensorflow.lite.** { *; }
-keep class org.tensorflow.lite.gpu.** { *; }

# Keep the GPU backend options
-keep class org.tensorflow.lite.gpu.GpuDelegateFactory$Options { *; }
-keepclassmembers class org.tensorflow.lite.gpu.GpuDelegateFactory$Options$GpuBackend { *; }