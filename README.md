# mach/ecs, an Entity Component System for Zig <a href="https://hexops.com"><img align="right" alt="Hexops logo" src="https://raw.githubusercontent.com/hexops/media/master/readme.svg"></img></a>

`mach/ecs` is an Entity Component System for Zig built from first-principles.

## Experimental

This is an _experimental_ Mach library, according to our [stability guarantees](https://machengine.org/next/docs/libs/):

> Experimental libraries may have their APIs change without much notice, and you may have to look at recent changes in order to update your code.

[Why this library is not declared stable yet](https://machengine.org/next/docs/libs/experimental/#ecs)

## Design principles:

* Initially a 100% clean-room implementation, working from first-principles. Later informed by research into how other ECS work, with advice from e.g. Bevy and Flecs authors at different points (thank you!)
* Solve the problems ECS solves, in a way that is natural to Zig and leverages Zig comptime.
* Fast. Optimal for CPU caches, multi-threaded, leverage comptime as much as is reasonable.
* Simple. Small API footprint, should be natural and fun - not like you're writing boilerplate.
* Enable other libraries to provide tracing, editors, visualizers, profilers, etc.

## ⚠️ in-development ⚠️

Under heavy development, not ready for use!

As development continues, we're publishing a blog series ["Let's build an Entity Component System from scatch"](https://devlog.hexops.com/categories/build-an-ecs/).

Join us in developing it, give us advice, etc. [on Discord](https://discord.gg/XNG3NZgCqp) or [follow updates on Twitter](https://twitter.com/machengine).

## Known issues

There are plenty of known issues, and things that just aren't implemented yet. And certainly many unknown issues, too.

* Missing multi-threading!
* Currently only handles entity management, no world management or scheduling. No global data, etc.
* Lack of API documentation (see "example" test)
* Missing hooks that would enable visualizing memory usage, # of entities, components, etc. and otherwise enable integration of editors/visualizers/profilers/etc.
* We have dense and sparse data, but no shared data yet.
* If many entities are deleted, iteration becomes slower due to needing to skip over entities in the free_slots set, we should add a .compact() method that allows for remediating this.
* If *tons* of entities are deleted, even with .compact(), memory would not be free'd / returned to the OS by the underlying components arrays. We could add a .compactAndFree() method to correct this.
* It would be nicer if there were configuration options for performing .compactAndFree() automatically, e.g. if the number of free entity slots is particularly high or something.
* Currently we do not expose an API for pre-allocating entities (i.e. allocating capacity up front) but that's very important for perf and memory usage in the real world.
* When entity is deleted, maybe via systems / an event/callback, need a way to be notified of destruction. Same with updated maybe.

See also the numerous TODOs in main.zig.

## Getting started

### Adding dependency

Create a `build.zig.zon` file in your project (replace `$LATEST_COMMIT` with the latest commit hash):

```
.{
    .name = "mypkg",
    .version = "0.1.0",
    .dependencies = .{
        .mach_ecs = .{
            .url = "https://github.com/hexops/mach-ecs/archive/$LATEST_COMMIT.tar.gz",
        },
    },
}
```

Run `zig build` in your project, and the compiler instruct you to add a `.hash = "..."` field next to `.url`.

Then use the dependency in your `build.zig`:

```zig
...
pub fn build(b: *Build) void {
    ...
    exe.addModule("mach-ecs", b.dependency("mach_ecs", .{
        .target = target,
        .optimize = optimize,
    }).module("mach-ecs"));
}
```

You may then `const ecs = @import("mach-ecs);` and use it.

### Usage

For usage, look at the tests in `src/main.zig`
