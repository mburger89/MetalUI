# ``MetalUI``

A GPU-accelerated UI framework for Swift, written as idiomatic Swift with SwiftUI as the design authority.

## Overview

MetalUI is modeled on gpui and draws every frame on the GPU. It runs on macOS (AppKit and Metal, the default), Linux and Windows. The project is experimental: the API still changes.

Start at the [MetalUI website](https://mburger89.github.io/MetalUI/), or go straight to <doc:GettingStarted>. The source is at [github.com/mburger89/MetalUI](https://github.com/mburger89/MetalUI).

## Topics

### Getting started

- <doc:GettingStarted>

### App and windows

- ``App``
- ``Window``
- ``Commands``
- ``CommandMenu``
- ``Menu``

### Components and state

- ``Component``
- ``EquatableComponent``
- ``State``
- ``Binding``
- ``Bindable``
- ``Environment``
- ``EnvironmentValues``
- ``Element``
- ``ElementBuilder``

### Layout

- ``HStack``
- ``VStack``
- ``ZStack``
- ``Grid``
- ``LazyVStack``
- ``LazyHStack``
- ``ScrollView``
- ``Spacer``
- ``Divider``
- ``Frame``
- ``Padding``

### Controls

- ``Button``
- ``Toggle``
- ``Picker``
- ``Slider``
- ``Stepper``
- ``List``
- ``Section``
- ``TextField``
- ``TextEditor``
- ``ProgressView``

### Text

- ``Text``
- ``Font``
- ``LocalizedStringKey``
- ``MarkdownView``
- ``CodeView``
- ``TextSystem``

### Drawing

- ``Color``
- ``Gradient``
- ``Path``
- ``Shape``
- ``Image``
- ``Icon``
- ``MetalView``
- ``Animation``
