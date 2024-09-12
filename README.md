<h1>
    <img src="./logo.png" width="64px" align="center">
    Cursor for ARM
</h1>

[Cursor](https://cursor.com) built for Linux and Windows ARM.

The official issue tracker has numerous issues ([#1532](https://github.com/getcursor/cursor/issues/1532) and [#1410](https://github.com/getcursor/cursor/issues/1410)) for official ARM support. Read the [FAQ](#faq) to learn how this works.

> [!NOTE]
> These are unofficial builds.

## Install

Download the [latest release](https://github.com/coder/cursor-arm/releases/latest) and execute it.

For Nix users, simply `nix build` and run.

## FAQ

### How is this possible?

Cursor is a closed-source fork of VS Code based on Electron that distributes using `AppImage`.

An `AppImage` is an executable archive that can be extracted with `7z`. The contents are virtually the same as the built and distributed archives of VS Code.

Overwriting the JavaScript for VS Code with Cursor's archive creates a Cursor build.

```bash
cp -R $cursorSrc/resources/app/out $vscodeSrc/resources/app/
```

See the [build process](./flake.nix#L48) to see exactly how this works.

### Shouldn't Cursor do this?

Yes. Hopefully they will!

### Is this stable?

Seemingly. The [build process](./flake.nix#L48) is quite simple. Try it for yourself!
