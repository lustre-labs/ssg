// IMPORTS ---------------------------------------------------------------------

import gleam/bool
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option}
import gleam/regexp.{Match}
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
/// This renderer is compatible with **v5.0.0** of the [jot](https://hexdocs.pm/jot/jot.html)
/// package **without** support for footnotes. If you'd like to add support for
/// footnotes, pull requests are welcome!
///
pub type Renderer(view) {
  Renderer(
    codeblock: fn(Dict(String, String), Option(String), String) -> view,
    emphasis: fn(List(view)) -> view,
    heading: fn(Dict(String, String), Int, List(view)) -> view,
    link: fn(
      jot.Destination,
      Dict(String, String),
      Dict(String, Dict(String, String)),
      Dict(String, String),
      List(view),
    ) ->
      view,
    paragraph: fn(Dict(String, String), List(view)) -> view,
    bullet_list: fn(jot.ListLayout, String, List(List(view))) -> view,
    raw_html: fn(String) -> view,
    strong: fn(List(view)) -> view,
    text: fn(String) -> view,
    code: fn(String) -> view,
    image: fn(
      jot.Destination,
      Dict(String, String),
      Dict(String, Dict(String, String)),
      Dict(String, String),
      String,
    ) ->
      view,
    linebreak: view,
    thematicbreak: view,
    inline_math: fn(String) -> view,
    display_math: fn(String) -> view,
    blockquote: fn(Dict(String, String), List(view)) -> view,
    span: fn(Dict(String, String), String) -> view,
    div: fn(Dict(String, String), List(view)) -> view,
  )
}

// CONSTRUCTORS ----------------------------------------------------------------

/// The default renderer generates some sensible Lustre elements from a djot
/// document. You can use this if you need a quick drop-in renderer for some
/// markup in a Lustre project.
///
/// > **Note**: this does not implement a rich renderer for maths expressions.
/// > Instead, this takes the same approach as djot's own syntax reference and
/// > renders a `<span>` that can be understood by external libraries like
/// > MathJax or KaTeX.
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
        html.code([attribute("data-lang", lang)], [html.text(code)]),
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
    link: fn(destination, references, reference_attributes, attributes, content) {
      let attributes = to_attributes(attributes)
      case destination {
        jot.Reference(ref) -> {
          let attributes = case dict.get(reference_attributes, ref) {
            Ok(attrs) -> list.append(attributes, to_attributes(attrs))
            Error(_) -> attributes
          }

          case dict.get(references, ref) {
            Ok(url) -> html.a([attribute.href(url), ..attributes], content)
            Error(_) ->
              html.a(
                [
                  attribute.href("#" <> linkify(ref)),
                  attribute.id(linkify("back-to-" <> ref)),
                  ..attributes
                ],
                content,
              )
          }
        }
        jot.Url(url) -> html.a([attribute("href", url), ..attributes], content)
      }
    },
    paragraph: fn(attrs, content) { html.p(to_attributes(attrs), content) },
    bullet_list: fn(layout, style, items) {
      let list_style_type =
        attribute.style("list-style-type", case style {
          "-" -> "'-'"
          "*" -> "disc"
          _ -> "circle"
        })

      html.ul([list_style_type], {
        list.map(items, fn(item) {
          case layout {
            jot.Tight -> html.li([], item)
            jot.Loose -> html.li([], [html.p([], item)])
          }
        })
      })
    },
    raw_html: fn(content) { element.unsafe_raw_html("", "div", [], content) },
    strong: fn(content) { html.strong([], content) },
    text: fn(text) { html.text(text) },
    code: fn(content) { html.code([], [html.text(content)]) },
    image: fn(destination, references, reference_attributes, attributes, alt) {
      let attributes = to_attributes(attributes)
      case destination {
        jot.Reference(ref) -> {
          let attributes = case dict.get(reference_attributes, ref) {
            Ok(attrs) -> list.append(attributes, to_attributes(attrs))
            Error(_) -> attributes
          }
          case dict.get(references, ref) {
            Ok(url) ->
              html.img([attribute.src(url), attribute.alt(alt), ..attributes])
            Error(_) -> html.text(ref)
          }
        }
        jot.Url(url) ->
          html.img([attribute.src(url), attribute.alt(alt), ..attributes])
      }
    },
    linebreak: html.br([]),
    thematicbreak: html.hr([]),
    inline_math: fn(math) {
      html.span([attribute.class("math inline")], [
        html.text("\\(" <> math <> "\\)"),
      ])
    },
    display_math: fn(math) {
      html.span([attribute.class("math display")], [
        html.text("\\[" <> math <> "\\]"),
      ])
    },
    blockquote: fn(attrs, content) {
      html.blockquote(to_attributes(attrs), content)
    },
    span: fn(attrs, content) {
      html.span(to_attributes(attrs), [html.text(content)])
    },
    div: fn(attrs, content) { html.div(to_attributes(attrs), content) },
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
  let options = regexp.Options(case_insensitive: False, multi_line: True)
  let assert Ok(re) = regexp.compile("^---\\n[\\s\\S]*?\\n---", options)

  case regexp.scan(re, document) {
    [Match(content: frontmatter, ..), ..] ->
      Ok(
        frontmatter
        |> string.drop_start(4)
        |> string.drop_end(4),
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
  let Document(content:, references:, reference_attributes:, footnotes: _) =
    jot.parse(content)

  content
  |> list.map(render_block(_, references, reference_attributes, renderer))
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
  let Document(content:, references:, reference_attributes:, footnotes: _) =
    jot.parse(content)

  content
  |> list.map(render_block(_, references, reference_attributes, renderer))
  |> Ok
}

fn render_block(
  block: jot.Container,
  references: Dict(String, String),
  reference_attributes: Dict(String, Dict(String, String)),
  renderer: Renderer(view),
) -> view {
  case block {
    jot.Paragraph(attrs, inline) -> {
      renderer.paragraph(
        attrs,
        list.map(inline, render_inline(
          _,
          references,
          reference_attributes,
          renderer,
        )),
      )
    }

    jot.Heading(attrs, level, inline) -> {
      renderer.heading(
        attrs,
        level,
        list.map(inline, render_inline(
          _,
          references,
          reference_attributes,
          renderer,
        )),
      )
    }

    jot.Codeblock(attrs, language, code) -> {
      renderer.codeblock(attrs, language, code)
    }

    jot.ThematicBreak -> {
      renderer.thematicbreak
    }

    jot.RawBlock(content) -> {
      renderer.raw_html(content)
    }

    jot.BulletList(layout, style, items) -> {
      renderer.bullet_list(
        layout,
        style,
        list.map(
          items,
          list.map(_, render_block(
            _,
            references,
            reference_attributes,
            renderer,
          )),
        ),
      )
    }
    jot.BlockQuote(attributes:, items:) -> {
      renderer.blockquote(
        attributes,
        list.map(items, render_block(
          _,
          references,
          reference_attributes,
          renderer,
        )),
      )
    }
    jot.Div(attributes:, items:) -> {
      renderer.div(
        attributes,
        list.map(items, render_block(
          _,
          references,
          reference_attributes,
          renderer,
        )),
      )
    }
  }
}

fn render_inline(
  inline: jot.Inline,
  references: Dict(String, String),
  reference_attributes: Dict(String, Dict(String, String)),
  renderer: Renderer(view),
) -> view {
  case inline {
    jot.Text(text) -> {
      renderer.text(text)
    }

    jot.NonBreakingSpace -> {
      renderer.text(" ")
    }

    jot.Link(content:, destination:, attributes:) -> {
      renderer.link(
        destination,
        references,
        reference_attributes,
        attributes,
        list.map(content, render_inline(
          _,
          references,
          reference_attributes,
          renderer,
        )),
      )
    }

    jot.Emphasis(content:) -> {
      renderer.emphasis(
        list.map(content, render_inline(
          _,
          references,
          reference_attributes,
          renderer,
        )),
      )
    }

    jot.Strong(content:) -> {
      renderer.strong(
        list.map(content, render_inline(
          _,
          references,
          reference_attributes,
          renderer,
        )),
      )
    }

    jot.Code(content:) -> {
      renderer.code(content)
    }

    jot.Image(content:, destination:, attributes:) -> {
      renderer.image(
        destination,
        references,
        reference_attributes,
        attributes,
        text_content(content),
      )
    }

    jot.Linebreak -> {
      renderer.linebreak
    }

    jot.Footnote(_) -> renderer.text("")

    jot.MathDisplay(content:) -> {
      renderer.display_math(content)
    }

    jot.MathInline(content:) -> {
      renderer.inline_math(content)
    }
    jot.Span(attributes:, content:) -> {
      renderer.span(attributes, text_content(content))
    }
  }
}

// UTILS -----------------------------------------------------------------------

fn linkify(text: String) -> String {
  let assert Ok(re) = regexp.from_string(" +")

  text
  |> regexp.split(re, _)
  |> string.join("-")
}

fn text_content(segments: List(jot.Inline)) -> String {
  use text, inline <- list.fold(segments, "")

  case inline {
    jot.Text(content) -> text <> content
    jot.NonBreakingSpace -> text <> " "
    jot.Link(content: content, attributes: _, destination: _) ->
      text <> text_content(content)
    jot.Emphasis(content) -> text <> text_content(content)
    jot.Strong(content) -> text <> text_content(content)
    jot.Code(content) -> text <> content
    jot.Image(_, _, destination: _) -> text
    jot.Linebreak -> text
    jot.Footnote(_) -> text
    jot.MathDisplay(_) -> text
    jot.MathInline(_) -> text
    jot.Span(attributes: _, content:) -> text <> text_content(content)
  }
}
