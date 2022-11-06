# SwiftIOPackagePluginTest

Swift Package Plugin POC for SwiftIO projects.

## Context and Background

SwiftIO is a project similar to Arduino: a development board with an SDK that lets you control the board's CPU's pins using code. However, it is much faster and programs are written for it using the Swift programming language instead of C++.

As of writing this README (November 6th, 2022), the only way to compile and generate working binaries for the SwiftIO boards are only possible using the [mm-sdk](https://github.com/madmachineio/mm-sdk) toolchain, which is incompatible with Xcode. You can compile SwiftIO projects using mm-sdk **only**, because of the need for a special fork of the Swift compiler, found [here](https://github.com/madmachineio/swift), including a bunch of scripts that are required for generating the final binaries SwiftIO boards can recognize, parse and run.

I found this a little annoying because that means I can only use Visual Studio Code for editing SwiftIO projects, when I wanted to use Apple's official IDE, Xcode.

So I came up with a solution: make up an Xcode-compatible toolchain bundle that contains all of mm-sdk's tools (except for the `mm` CLI) and made special scripts for Xcode that will allow developers to compile SwiftIO projects from within Xcode.

As of right now, you still need to use the command line (and have a working SwiftIO toolchain bundle installed in one of the Xcode toolchain directories, which I am not providing a tutorial on how to make **yet**) in order to compile using only the Swift Package Manager:

```
$ swift package plugin build
```

and there are **still** many issues with this, however performing the necessary (currently undocumented, further research+toolchain making tutorial needed) steps for satisfying the Swift Package Plugin API's security constraints, I successfully built a working binary, ready to be loaded into both the original SwiftIO board as well as the new (and still unreleased) SwiftIO Feather board, completely replacing the need for the `mm` CLI for macOS users.

## The Goal of this Repo

The goal of this repo is to make a fully working simple demo SwiftIO project that is compilable via Xcode and doesn't require using the command line for compiling **at all**.
