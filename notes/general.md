# Profiling
ValGrind is the preferred profiling method (over nimprof builtin) with
visualization using kCacheGrind.

**Compiling**
You must set the following comiple flags:

```nim c --profiler:on --stacktrace:on main```

You may then execute the program as follows:

```valgrind --tool=callgrind -v ./main```

This will generate a `callgrind.out.xxxx` file that you can open in 
kCacheGrind.