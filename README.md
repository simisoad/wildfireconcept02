

# Wildfire Response RTS - A Godot Engine Tech Demo

[![Godot Version](https://img.shields.io/badge/Godot-4.x-blue.svg)](https://godotengine.org)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE.md)
![Status](https://img.shields.io/badge/Status-In%20Development-orange.svg)

**A prototype for a Real-Time Strategy (RTS) game focused on wildfire management, built upon a custom, high-performance world streaming system for the Godot Engine.**

![Screenshot of the game world](https://via.placeholder.com/800x450.png?text=Insert+GIF+or+Compelling+Screenshot+Here)
*(**Note:** A visual is critical! Replace the placeholder above with a GIF or screenshot showing the dynamically generated terrain.)*

## About The Project

This project is a technical exploration into creating vast, detailed game worlds based on real-world geospatial data. The goal is to build the foundation for an RTS game where the player coordinates aerial and ground units to combat dynamically spreading forest fires.

This repository contains the second iteration of the concept, evolving from an earlier 2D proof-of-concept ([WildFireConcept on itch.io](https://nomis3d.itch.io/wildfireconcept)). The primary focus of this version is the development of a robust and scalable back-end for handling massive environments.

## Core Technical Features

The project's foundation is a custom-built streaming and rendering pipeline designed to handle large datasets efficiently.

*   **Dynamic World Streaming:** The world is streamed dynamically from `.mbtiles` databases containing OpenStreetMap (OSM) vector and raster data. This is managed by a thread-safe `DataSourceManager` that handles I/O operations in a dedicated worker pool to prevent stalling the main thread.

*   **Multithreaded Processing Pipeline:** Once tile data is loaded, it is passed to a `ChunkGenerator` which uses a separate pool of worker threads to process vector data, generate logic maps, and prepare rendering data. This parallel processing architecture is key to maintaining a smooth frame rate while loading and building new world segments.

*   **Advanced Level of Detail (LOD) System:** The `WorldStreamer` manages the level of detail for each terrain chunk not by simple distance, but by the **screen-space area** it occupies. This results in a more efficient and visually consistent LOD selection, ensuring high-resolution detail is only rendered where it's most impactful.

*   **High-Performance C++ GDExtension:** To handle the computationally intensive task of rasterizing polygon vector data into logic maps, a custom C++ GDExtension (`RasterizerUtils`) was developed. This moves the heaviest processing from GDScript to C++, yielding a significant performance increase and enabling real-time data processing.

*   **Procedural Geometry & Shading:** The final visuals are generated procedurally. Terrain surfaces are rendered using a single `PlaneMesh` per chunk, with a custom shader that uses the generated logic maps to blend different terrain textures (water, forest, fields, etc.). Vegetation is placed using `MultiMeshInstance3D` nodes, populated based on the processed data.

## Current Status

The project is currently in the **prototyping phase**. The core focus is on optimizing and stabilizing the world-streaming and procedural generation pipeline.

*   ✅ **Working:** Data loading from `.mbtiles`, multithreaded rasterization via C++, LOD management, and procedural generation of terrain chunks.
*   🚧 **In Progress:** Optimizing the replacement and management of sub-chunks during LOD transitions, improving performance for vegetation rendering, and refining the terrain shader.

## Getting Started

To run this project, you will need to set up the environment, compile the GDExtension, and provide the necessary data files.

### 1. Prerequisites

*   Godot Engine 4.x
*   A C++ compiler toolchain (GCC, Clang, or MSVC) and SCons for building the GDExtension.
*   The required Godot add-ons.

### 2. Installation & Setup

1.  **Clone the repository:**
    ```sh
    git clone https://github.com/your-username/your-repo-name.git
    cd your-repo-name
    ```

2.  **Install Add-ons:**
    This project requires the following third-party add-ons. Please download them and place them in the `addons/` directory:
    *   [godot-sqlite](https://github.com/2shady4u/godot-sqlite)
    *   [geo-tile-loader](https://github.com/nomis-3d/geo-tile-loader) (*Assuming you have another repo for this, otherwise link to the original*)

3.  **Compile the GDExtension:**
    Navigate to the `rasterizer_utils` directory and compile the C++ library. For detailed instructions, see the [Godot GDExtension documentation](https://docs.godotengine.org/en/stable/tutorials/scripting/gdextension/compiling_gdextension.html).
    ```sh
    cd rasterizer_utils
    scons
    ```

4.  **Provide Data Files:**
    The large `.mbtiles` databases are not included in this repository. You will need to source your own OSM data or use a smaller sample set.
    *   Create a directory: `res://db/`
    *   Place your vector and raster `.mbtiles` files inside.
    *   Update the file paths in `DataSourceManager.gd` to match your filenames. The code currently expects:
        *   `res://db/languedoc-roussillon.mbtiles`
        *   `res://db/senti.mbtiles`

5.  **Run the Project:**
    Open the project in the Godot Engine and run the main scene (`Main.tscn`).


