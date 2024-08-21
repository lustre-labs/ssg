// IMPORTS ---------------------------------------------------------------------

import gleam/bool
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option}
import gleam/regex.{Match}
import gleam/result
import gleam/string
import jot.{Document}
import lustre/attribute.{attribute}
import lustre/element.{type Element}
import lustre/element/html
import tom.{type Toml}

// TYPES -----------------------------------------------------------------------

/// A renderer for a djot document knows how to turn each block or inline element
/// into some custom view. That view could be anything, but it's typically a
/// Lustre element.
///
/// Some ideas for other renderers include:
///
/// - A renderer that turns a djot document into a JSON object
/// - A renderer that generates a table of contents
/// - A renderer that generates Nakai elements instead of Lustre ones
///
/// Sometimes a custom renderer might need access to the TOML metadata of a
/// document. For that, take a look at the [`render_with_metadata`](#render_with_metadata)
/// function.
///
/// This renderer is compatible with **v1.0.0** of the [jot](https://hexdocs.pm/jot/jot.html)
/// package.
///
pub type Renderer(view) {
  Renderer(
    codeblock: fn(Dict(String, String), Option(String), String) -> view,
    emphasis: fn(List(view)) -> view,
    heading: fn(Dict(String, String), Int, List(view)) -> view,
    link: fn(jot.Destination, Dict(String, String), List(view)) -> view,
    paragraph: fn(Dict(String, String), List(view)) -> view,
    strong: fn(List(view)) -> view,
    text: fn(String) -> view,
    code: fn(String) -> view,
    image: fn(jot.Destination, String) -> view,
    linebreak: fn() -> view,
  )
}

// CONSTRUCTORS ----------------------------------------------------------------

/// The default renderer generates some sensible Lustre elements from a djot
/// document. You can use this if you need a quick drop-in renderer for some
/// markup in a Lustre project.
///
pub fn default_renderer() -> Renderer(Element(msg)) {
  let to_attributes = fn(attrs) {
    use attrs, key, val <- dict.fold(attrs, [])
    [attribute(key, val), ..attrs]
  }

  Renderer(
    codeblock: fn(attrs, lang, code) {
      let lang = option.unwrap(lang, "text")
      html.pre(to_attributes(attrs), [
        html.code([attribute("data-lang", lang)], [element.text(code)]),
      ])
    },
    emphasis: fn(content) { html.em([], content) },
    heading: fn(attrs, level, content) {
      case level {
        1 -> html.h1(to_attributes(attrs), content)
        2 -> html.h2(to_attributes(attrs), content)
        3 -> html.h3(to_attributes(attrs), content)
        4 -> html.h4(to_attributes(attrs), content)
        5 -> html.h5(to_attributes(attrs), content)
        6 -> html.h6(to_attributes(attrs), content)
        _ -> html.p(to_attributes(attrs), content)
      }
    },
    link: fn(destination, references, content) {
      case destination {
        jot.Reference(ref) ->
          case dict.get(references, ref) {
            Ok(url) -> html.a([attribute.href(url)], content)
            Error(_) ->
              html.a(
                [
                  attribute.href("#" <> linkify(ref)),
                  attribute.id(linkify("back-to-" <> ref)),
                ],
                content,
              )
          }
        jot.Url(url) -> html.a([attribute("href", url)], content)
      }
    },
    paragraph: fn(attrs, content) { html.p(to_attributes(attrs), content) },
    strong: fn(content) { html.strong([], content) },
    text: fn(text) { element.text(text) },
    code: fn(content) { html.code([], [element.text(content)]) },
    image: fn(destination, alt) {
      case destination {
        jot.Reference(ref) ->
          html.img([attribute.src("#" <> linkify(ref)), attribute.alt(alt)])
        jot.Url(url) -> html.img([attribute.src(url), attribute.alt(alt)])
      }
    },
    linebreak: fn() { html.br([]) },
  )
}

// QUERIES ---------------------------------------------------------------------

/// Extract the frontmatter string from a djot document. Frontmatter is anything
/// between two lines of three dashes, like this:
///
/// ```djot
/// ---
/// title = "My Document"
/// ---
///
/// # My Document
///
/// ...
/// ```
///
/// The document **must** start with exactly three dashes and a newline for there
/// to be any frontmatter. If there is no frontmatter, this function returns
/// `Error(Nil)`,
///
pub fn frontmatter(document: String) -> Result(String, Nil) {
  use <- bool.guard(!string.starts_with(document, "---"), Error(Nil))
  let options = regex.Options(case_insensitive: False, multi_line: True)
  let assert Ok(re) = regex.compile("^---\\n[\\s\\S]*?\\n---", options)

  case regex.scan(re, document) {
    [Match(content: frontmatter, ..), ..] ->
      Ok(
        frontmatter
        |> string.drop_left(4)
        |> string.drop_right(4),
      )
    _ -> Error(Nil)
  }
}

/// Extract the TOML metadata from a djot document. This takes the [`frontmatter`](#frontmatter)
/// and parses it as TOML. If there is *no* frontmatter, this function returns
/// an empty dictionary.
///
/// If the frontmatter is invalid TOML, this function returns a TOML parse error.
///
pub fn metadata(document: String) -> Result(Dict(String, Toml), tom.ParseError) {
  case frontmatter(document) {
    Ok(frontmatter) -> tom.parse(frontmatter)
    Error(_) -> Ok(dict.new())
  }
}

/// Extract the djot content from a document with optional frontmatter. If the
/// document does not have frontmatter, this acts as an identity function.
///
pub fn content(document: String) -> String {
  let toml = frontmatter(document)

  case toml {
    Ok(toml) -> string.replace(document, "---\n" <> toml <> "\n---", "")
    Error(_) -> document
  }
}

// CONVERSIONS -----------------------------------------------------------------

/// Render a djot document using the given renderer. If the document contains
/// [`frontmatter`](#frontmatter) it is stripped out before rendering.
///
pub fn render(document: String, renderer: Renderer(view)) -> List(view) {
  let content = content(document)
  let Document(content, references) = jot.parse(content)

  content
  |> list.map(render_block(_, references, renderer))
}

/// Render a djot document using the given renderer. TOML metadata is extracted
/// from the document's frontmatter and passed to the renderer. If the frontmatter
/// is invalid TOML this function will return the TOML parse error, but if there
/// is no frontmatter to parse this function will succeed and just pass an empty
/// dictionary to the renderer.
///
pub fn render_with_metadata(
  document: String,
  renderer: fn(Dict(String, Toml)) -> Renderer(view),
) -> Result(List(view), tom.ParseError) {
  let toml = frontmatter(document)
  use metadata <- result.try(
    toml
    |> result.unwrap("")
    |> tom.parse,
  )

  let content = content(document)
  let renderer = renderer(metadata)
  let Document(content, references) = jot.parse(content)

  content
  |> list.map(render_block(_, references, renderer))
  |> Ok
}

fn render_block(
  block: jot.Container,
  references: Dict(String, String),
  renderer: Renderer(view),
) -> view {
  case block {
    jot.Paragraph(attrs, inline) -> {
      renderer.paragraph(
        attrs,
        list.map(inline, render_inline(_, references, renderer)),
      )
    }

    jot.Heading(attrs, level, inline) -> {
      renderer.heading(
        attrs,
        level,
        list.map(inline, render_inline(_, references, renderer)),
      )
    }

    jot.Codeblock(attrs, language, code) -> {
      renderer.codeblock(attrs, language, code)
    }
  }
}

fn render_inline(
  inline: jot.Inline,
  references: Dict(String, String),
  renderer: Renderer(view),
) -> view {
  case inline {
    jot.Text(text) -> {
      renderer.text(text)
    }

    jot.Link(content, destination) -> {
      renderer.link(
        destination,
        references,
        list.map(content, render_inline(_, references, renderer)),
      )
    }

    jot.Emphasis(content) -> {
      renderer.emphasis(
        list.map(content, render_inline(_, references, renderer)),
      )
    }

    jot.Strong(content) -> {
      renderer.strong(list.map(content, render_inline(_, references, renderer)))
    }

    jot.Code(content) -> {
      renderer.code(content)
    }

    jot.Image(alt, destination) -> {
      renderer.image(destination, text_content(alt))
    }

    jot.Linebreak -> {
      renderer.linebreak()
    }
  }
}

// UTILS -----------------------------------------------------------------------

fn linkify(text: String) -> String {
  let assert Ok(re) = regex.from_string(" +")

  text
  |> regex.split(re, _)
  |> string.join("-")
}

fn text_content(segments: List(jot.Inline)) -> String {
  use text, inline <- list.fold(segments, "")

  case inline {
    jot.Text(content) -> text <> content
    jot.Link(content, _) -> text <> text_content(content)
    jot.Emphasis(content) -> text <> text_content(content)
    jot.Strong(content) -> text <> text_content(content)
    jot.Code(content) -> text <> content
    jot.Image(_, _) -> text
    jot.Linebreak -> text
  }
}
