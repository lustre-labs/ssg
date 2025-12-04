# lustre_ssg

[![Package Version](https://img.shields.io/hexpm/v/lustre_ssg)](https://hex.pm/packages/lustre_ssg)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/lustre_ssg/)

A simple static site generator for [Lustre](https://github.com/lustre-labs/lustre)
projects, written in pure Gleam. `lustre_ssg` will run on both Gleam's Erlang and
JavaScript targets. If you're using the JavaScript target, `lustre_ssg` is tested
to work on both Node.js and Deno!

## What it is

`lustre_ssg` is a low-config static site generator for simple things like a
personal blog or documentation site. Declare your routes, tell `lustre_ssg` how
to render them, and it will spit out a bunch of HTML files for you.

## What it is not

`lustre_ssg` is not a batteries-included framework for generating static sites.
There is no CLI, no built-in server, no fancy data fetching, and no client-side
hydration. If you need those things, you will have to build them yourself!

## Usage

1. Add `lustre_ssg` as a dependency to your Gleam project:

```sh
$ gleam add lustre_ssg
```

2. Create a `build.gleam` file in your project's `dev` directory.

3. Import `lustre/ssg` and configure your routes:

```gleam
import gleam/list
import gleam/io

// Some data for your site
import app/data/posts

// Some functions for rendering pages
import app/page/index
import app/page/blog
import app/page/post

// Import the static site generator
import lustre/ssg

pub fn main() {
  let posts =
    list.map(posts.all(), fn(post) { #(post.id, post) })
    |> dict.from_list()

  let build = ssg.new("./priv")
    |> ssg.add_static_route("/", index.view())
    |> ssg.add_static_route("/blog", blog.view(posts.all()))
    |> ssg.add_dynamic_route("/blog", posts, post.view)
    |> ssg.build

  case build {
    Ok(_) -> io.println("Build succeeded!")
    Error(e) -> {
      echo e
      io.println("Build failed!")
    }
  }
}
```

4. Run the build script to generate your static site!

```sh
$ gleam run -m build
```

```sh
$ tree priv

priv
├── blog
│   ├── wibble.html
│   ├── wobble.html
│   └── ...
├── blog.html
└── index.html
```
