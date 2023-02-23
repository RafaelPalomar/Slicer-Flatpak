# Slicer-Flatpak

Slicer-Flatpak is a tool that generates a Flatpak package for the 3D Slicer
application. 3D Slicer is a free and open-source software package for image
analysis and scientific visualization, developed by an international community
of researchers and clinicians. The software is widely used in medical research,
clinical care, and education, and is designed to be extensible, flexible, and
easy to use.

Flatpak is a package manager that enables developers to distribute applications
for Linux-based operating systems. By using Flatpak, Slicer-Flatpak simplifies
the process of installing and running 3D Slicer on a wide variety of Linux
distributions.

## Getting Started

### Prerequisites

Before using Slicer-Flatpak, make sure you have the following software installed on your system:

- [Flatpak](https://flatpak.org/)
- [Flatpak Builder](https://docs.flatpak.org/en/latest/flatpak-builder.html)

In addition, you will need to add the Flathub repository:

``` sh
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

```
and install the following Flatpak dependencies to build the Flatpak package:

- `org.kde.Sdk/x86_64/5.15-22.08`
- `org.kde.Platform/x86_64/5.15-22.08`
- `io.qt.qtwebengine.BaseApp/x86_64/5.15-22.08`

You can then install these dependencies by issuing the following command: 

``` sh
sudo flatpak install org.kde.Sdk/x86_64/5.15 org.kde.Platform/x86_64/5.15-22.08 io.qt.qtwebengine.BaseApp/x86_64/5.15-22.08

```

### Organization of the repository

This repository contains a `git submodule` pointing to
`https://github.com/RafaelPalomar/org.slicer.Slicer`. By default, this submodule
will be checkout in the root of the project:

```
Slicer-Flatpak
             ├── org.slicer.Slicer # This is a git submodule
             ...
```

The generated manifest will be placed in that directory.

### Usage

To generate the Flatpak package, run:

```
make all
```

To enable debugging output, set the `DEBUG` variable to `true`:

```
DEBUG=true make all
```

### Building the Flatpak

Finally, in order to build the Flatpak, you can invoke the `flatpak-builder`
from the `org.slicer.Slicer` directory.

``` sh
cd org.slicer.Slicer
flatpak-builder --force-clean build-dir org.slicer.Slicer.yaml --verbose
```

## Customization

Slicer-Flatpak allows you to customize various variables. The following variables can be set by the user:

- `SLICER_GIT_REPOSITORY`: The Git repository where the 3D Slicer source code is located. Default: `https://github.com/Slicer/Slicer`.
- `SLICER_GIT_TAG`: The Git tag to use for the 3D Slicer source code. Default: `main`.
- `PLATFORM_VERSION`: The version of the Flatpak platform. Default: `5.15`.
- `QTWEBENGINE_VERSION`: The version of the QtWebEngine Flatpak dependency. Default: `5.15-22.08`.
- `SDK_VERSION`: The version of the Flatpak SDK. Default: the value of `PLATFORM_VERSION`.
- `DEBUG`: If set to `true`, enables debugging output. Default: `false`.

To set a variable, use the following syntax:

```
VARIABLE=value make all
```

## License

Slicer-Flatpak is released under the [BSD 3-Clause License](https://opensource.org/licenses/BSD-3-Clause).

