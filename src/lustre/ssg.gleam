// IMPORTS ---------------------------------------------------------------------

import gleam/list
import gleam/map.{Map}
import gleam/option.{None, Option, Some}
import gleam/regex
import gleam/string
import lustre/element.{Element}
import simplifile

// MAIN ------------------------------------------------------------------------

/// Initialise a new configuration for the static site generator. If you pass a
/// relative path it will be resolved relative to the current working directory,
/// _not_ the directory of the Gleam file.
/// 
pub fn new(out_dir: String) -> Config(NoStaticRoutes, NoStaticDir) {
  Config(out_dir, None, [])
}

/// Generate the static site. This will delete the output directory if it already
/// exists and then generate all of the routes configured. If a static assets
/// directory has been configured, its contents will be recursively copied into 
/// the output directory.
/// 
pub fn build(config: Config(HasStaticRoutes, has_static_dir)) {
  let Config(out_dir, static_dir, routes) = config

  // There's nothing like Node's `path` module for Gleam yet so working with
  // paths and directories is a bit primitive. We'll be concating all of our
  // routes to this `out_dir` and they'll all start with a leading slash. I don't
  // want to have to deal with any weirdness of double slashes so we're just
  // removing it from the out_dir if it's there.
  let out_dir = trim_slash(out_dir)

  // Every build will generate a clean directory. Any files that already exist
  // will be wiped, and any previously-generated routes will also be deleted and
  // regenerated.
  let _ = simplifile.delete(out_dir)
  let assert Ok(_) = case static_dir {
    Some(path) -> simplifile.copy_directory(path, out_dir)
    None -> simplifile.create_directory_all(out_dir)
  }
  let routes = list.sort(routes, fn(a, b) { string.compare(a.path, b.path) })
  use route <- list.each(routes)

  case route {
    Static("/", el) -> {
      let path = out_dir <> "/index.html"
      let html = element.to_string(el)
      let assert Ok(_) = simplifile.write(html, path)

      Nil
    }

    Static(path, el) -> {
      let #(path, name) = last_segment(path)
      let _ = simplifile.create_directory_all(out_dir <> path)
      let path = out_dir <> trim_slash(path) <> "/" <> name <> ".html"
      let html = element.to_string(el)
      let assert Ok(_) = simplifile.write(html, path)

      Nil
    }

    Dynamic(path, pages) -> {
      let _ = simplifile.create_directory_all(out_dir <> path)
      use #(page, el) <- list.each(map.to_list(pages))
      let path = out_dir <> trim_slash(path) <> "/" <> routify(page) <> ".html"
      let html = element.to_string(el)
      let assert Ok(_) = simplifile.write(html, path)

      Nil
    }
  }
}

// TYPES -----------------------------------------------------------------------

/// The `Config` type tells `lustre_ssg` how to generate your site. It includes
/// things like the output directory and any routes you have configured.
/// 
/// The type parameters are used to track different facts about the configuration
/// and prevent silly things from happening like building a site with no guaranteed
/// routes.
/// 
pub opaque type Config(has_static_routes, has_static_dir) {
  Config(out_dir: String, static_dir: Option(String), routes: List(Route))
}

/// This type is used to tag the `Config` through the different builder functions.
/// It indicates a configuration that will not generate any static routes.
/// 
/// Your configuration must have at least one static route before it can be passed
/// to `build`. This is to prevent you from accidentally building a completely
/// empty site.
/// 
pub type NoStaticRoutes

/// This type is used to tag the `Config` through the different builder functions.
/// It indicates a configuration that does not have a statica ssets directory to
/// copy.
/// 
pub type NoStaticDir

/// This type is used to tag the `Config` through the different builder functions.
/// It indicates a configuration that will generate least one static route.
/// 
pub type HasStaticRoutes

/// This type is used to tag the `Config` through the different builder functions.
/// It indicates a configuration that has a static assets directory to copy.
/// 
pub type HasStaticDir

type Route {
  Static(path: String, page: Element(Nil))
  Dynamic(path: String, pages: Map(String, Element(Nil)))
}

// BUILDERS --------------------------------------------------------------------

/// Configure a static route to be generated. The path should be the route that
/// the page will be available at when served by a HTTP server. For example the
/// path "/blog" would be available at "https://your_site.com/blog".
/// 
/// You need to add at least one static route before you can build your site. This
/// is to prevent you from providing empty dynamic routes and accidentally building
/// nothing. 
/// 
/// Paths are converted to kebab-case and lowercased. This means that the path
/// "/Blog" will be available at "/blog" and and "/About me" will be available at
/// "/about-me".
/// 
pub fn add_static_route(
  config: Config(has_static_routes, has_static_dir),
  path: String,
  page: Element(a),
) -> Config(HasStaticRoutes, has_static_dir) {
  let Config(out_dir, static_dir, routes) = config
  let route = Static(routify(path), element.map(page, fn(_) { Nil }))

  Config(out_dir, static_dir, [route, ..routes])
}

/// Configure a map of dynamic routes to be generated. As with `add_static_route`
/// the base path should be the route that each page will be available at when
/// served by a HTTP server.
/// 
/// The initial path is the base for all dynamic routes to be generated. The
/// keys of the `data` map will be used to generate the dynamic routes. For
/// example, to generate dynamic routes for a blog where each page is a post
/// with the route "/blog/:post" you might do:
/// 
/// ```gleam
/// let posts = [
///   #("hello-world", Post(...)),
///   #("why-lustre-is-great", Post(...)),
/// ]
/// 
/// ...
/// 
/// ssg.config("./dist")
/// |> ...
/// |> ssg.add_dynamic_route("/blog", posts, render_post)
/// ```
/// 
/// Paths are converted to kebab-case and lowercased. This means that the path
/// "/Blog" will be available at "/blog" and and "/About me" will be available at
/// "/about-me".
/// 
pub fn add_dynamic_route(
  config: Config(has_static_routes, has_static_dir),
  path: String,
  data: Map(String, a),
  page: fn(a) -> Element(b),
) -> Config(has_static_routes, has_static_dir) {
  let Config(out_dir, static_dir, routes) = config
  let route = {
    let path = routify(path)
    let pages =
      map.map_values(
        data,
        fn(_, data) { element.map(page(data), fn(_) { Nil }) },
      )

    Dynamic(path, pages)
  }

  Config(out_dir, static_dir, [route, ..routes])
}

///
/// 
pub fn add_static_dir(
  config: Config(has_static_routes, NoStaticDir),
  path: String,
) -> Config(has_static_routes, HasStaticDir) {
  let Config(out_dir, _, routes) = config
  let static_dir = routify(path)

  Config(out_dir, Some(static_dir), routes)
}

// UTILS -----------------------------------------------------------------------

fn routify(path: String) -> String {
  let assert Ok(whitespace) = regex.from_string("\\s+")

  regex.split(whitespace, path)
  |> string.join("-")
  |> string.lowercase
}

fn trim_slash(path: String) -> String {
  case string.ends_with(path, "/") {
    True -> string.drop_right(path, 1)
    False -> path
  }
}

fn last_segment(path: String) -> #(String, String) {
  let assert Ok(segments) = regex.from_string("(.*/)+?(.+)")
  let assert [regex.Match(content: _, submatches: [Some(leading), Some(last)])] =
    regex.scan(segments, path)

  #(leading, last)
}
