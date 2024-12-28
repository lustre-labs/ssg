// IMPORTS ---------------------------------------------------------------------

import commonmark
import commonmark/ast.{
  type AlertLevel, type BlockNode, type Document, type EmphasisMarker,
  type InlineNode, type ListItem, type OrderedListMarker, type Reference,
  type UnorderedListMarker, Document,
}
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option}
import gleam/regexp.{Match}
import gleam/result
import gleam/string
import lustre/attribute.{attribute}
import lustre/element.{type Element}
import lustre/element/html
import tom.{type Toml}

// TYPES -----------------------------------------------------------------------

/// A renderer for a markdown document knows how to turn each block or inline element
/// into some custom view. That view could be anything, but it's typically a
/// Lustre element.
///
/// Some ideas for other renderers include:
///
/// - A renderer that turns a markdown document into a JSON object
/// - A renderer that generates a table of contents
/// - A renderer that generates Nakai elements instead of Lustre ones
///
/// Sometimes a custom renderer might need access to the TOML metadata of a
/// document. For that, take a look at the [`render_with_metadata`](#render_with_metadata)
/// function.
///
/// This renderer is compatible with **v0.1.8** of the [commonmark](https://hexdocs.pm/commonmark/commonmark.html)
/// package.
///
pub type Renderer(view) {
  Renderer(
    horizontal_break: fn() -> view,
    heading: fn(Int, List(view)) -> view,
    codeblock: fn(Option(String), Option(String), String) -> view,
    html_block: fn(String) -> view,
    paragraph: fn(List(view)) -> view,
    block_quote: fn(List(view)) -> view,
    alert_block: fn(AlertLevel, List(view)) -> view,
    ordered_list: fn(List(view), Int, OrderedListMarker) -> view,
    unordered_list: fn(List(view), UnorderedListMarker) -> view,
    list_item: fn(List(view)) -> view,
    tight_list_item: fn(List(view)) -> view,
    code_span: fn(String) -> view,
    emphasis: fn(List(view), EmphasisMarker) -> view,
    strong_emphasis: fn(List(view), EmphasisMarker) -> view,
    strike_through: fn(List(view)) -> view,
    link: fn(List(view), Option(String), String) -> view,
    reference_link: fn(List(view), String) -> view,
    image: fn(String, Option(String), String) -> view,
    reference_image: fn(String, String) -> view,
    uri_autolink: fn(String) -> view,
    email_autolink: fn(String) -> view,
    html_inline: fn(String) -> view,
    plain_text: fn(String) -> view,
    hard_line_break: fn() -> view,
    soft_line_break: fn() -> view,
  )
}

// CONSTRUCTORS ----------------------------------------------------------------

/// The default renderer generates some sensible Lustre elements from a markdown
/// document. You can use this if you need a quick drop-in renderer for some
/// markup in a Lustre project.
///
pub fn default_renderer() -> Renderer(Element(msg)) {
  Renderer(
    horizontal_break: fn() { html.hr([]) },
    heading: fn(level, contents) {
      case level {
        1 -> html.h1([], contents)
        2 -> html.h2([], contents)
        3 -> html.h3([], contents)
        4 -> html.h4([], contents)
        5 -> html.h5([], contents)
        6 -> html.h6([], contents)
        _ -> html.p([], contents)
      }
    },
    codeblock: fn(info, _, contents) {
      html.pre([], [
        html.code(
          [attribute.class("language-" <> option.unwrap(info, "text"))],
          [element.text(contents)],
        ),
      ])
    },
    html_block: fn(html) { element.text(html) },
    paragraph: fn(contents) { html.p([], contents) },
    block_quote: fn(contents) { html.blockquote([], contents) },
    alert_block: fn(_, contents) { html.blockquote([], contents) },
    ordered_list: fn(contents, start, _) {
      html.ol([attribute.attribute("start", start |> int.to_string)], contents)
    },
    unordered_list: fn(contents, _) { html.ul([], contents) },
    list_item: fn(contents) {
      html.li([], contents |> list.map(fn(item) { html.p([], [item]) }))
    },
    tight_list_item: fn(contents) { html.li([], contents) },
    code_span: fn(contents) { html.code([], [element.text(contents)]) },
    emphasis: fn(contents, _) { html.em([], contents) },
    strong_emphasis: fn(contents, _) { html.strong([], contents) },
    strike_through: fn(contents) { html.del([], contents) },
    link: fn(contents, title, href) {
      html.a(
        [
          attribute.href(href),
          case title {
            option.Some(t) -> attribute.attribute("title", t)
            option.None -> attribute.none()
          },
        ],
        contents,
      )
    },
    reference_link: fn(contents, href) {
      html.a([attribute.href(href)], contents)
    },
    image: fn(alt, title, href) {
      html.img([
        attribute.alt(alt),
        attribute.href(href),
        case title {
          option.Some(t) -> attribute.attribute("title", t)
          option.None -> attribute.none()
        },
      ])
    },
    reference_image: fn(alt, ref) {
      html.img([attribute.alt(alt), attribute.href(ref)])
    },
    uri_autolink: fn(href) {
      html.a([attribute.href(href)], [element.text(href)])
    },
    email_autolink: fn(href) {
      html.a([attribute.href(href)], [element.text(href)])
    },
    html_inline: fn(html) { element.text(html) },
    plain_text: fn(contents) { element.text(contents) },
    hard_line_break: fn() { html.br([]) },
    soft_line_break: fn() { html.text(" ") },
  )
}

// QUERIES ---------------------------------------------------------------------

/// Extract the frontmatter string from a markdown document. Frontmatter is anything
/// between two lines of three dashes, like this:
///
/// ```markdown
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
        |> string.drop_left(4)
        |> string.drop_right(4),
      )
    _ -> Error(Nil)
  }
}

/// Extract the TOML metadata from a markdown document. This takes the [`frontmatter`](#frontmatter)
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

/// Extract the markdown content from a document with optional frontmatter. If the
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

/// Render a markdown document using the given renderer. If the document contains
/// [`frontmatter`](#frontmatter) it is stripped out before rendering.
///
pub fn render(document: String, renderer: Renderer(view)) -> List(view) {
  let content = content(document)
  let Document(content, references) = commonmark.parse(content)
  io.debug(content)

  content
  |> list.map(render_block(_, references, renderer))
}

/// Render a markdown document using the given renderer. TOML metadata is extracted
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
  let Document(content, references) = commonmark.parse(content)

  content
  |> list.map(render_block(_, references, renderer))
  |> Ok
}

fn render_block(
  block: BlockNode,
  references: Dict(String, Reference),
  renderer: Renderer(view),
) -> view {
  case block {
    ast.HorizontalBreak -> renderer.horizontal_break()
    ast.Heading(level, contents) ->
      renderer.heading(
        level,
        list.map(contents, render_inline(_, references, renderer)),
      )
    ast.CodeBlock(info, full_info, contents) ->
      renderer.codeblock(info, full_info, contents)
    ast.HtmlBlock(html) -> renderer.html_block(html)
    ast.Paragraph(contents) ->
      renderer.paragraph(
        list.map(contents, render_inline(_, references, renderer)),
      )
    ast.BlockQuote(contents) ->
      renderer.block_quote(
        list.map(contents, render_block(_, references, renderer)),
      )
    ast.AlertBlock(level, contents) ->
      renderer.alert_block(
        level,
        list.map(contents, render_block(_, references, renderer)),
      )
    ast.OrderedList(contents, start, marker) ->
      renderer.ordered_list(
        list.map(contents, render_list_item(_, references, renderer)),
        start,
        marker,
      )
    ast.UnorderedList(contents, marker) ->
      renderer.unordered_list(
        list.map(contents, render_list_item(_, references, renderer)),
        marker,
      )
  }
}

fn render_list_item(
  item: ListItem,
  references: Dict(String, Reference),
  renderer: Renderer(view),
) -> view {
  case item {
    ast.ListItem(contents) ->
      renderer.list_item(
        list.map(contents, render_block(_, references, renderer)),
      )
    ast.TightListItem(contents) ->
      renderer.tight_list_item(
        list.map(contents, render_block(_, references, renderer)),
      )
  }
}

fn render_inline(
  inline: InlineNode,
  references: Dict(String, Reference),
  renderer: Renderer(view),
) -> view {
  case inline {
    ast.CodeSpan(contents) -> renderer.code_span(contents)
    ast.Emphasis(contents, marker) ->
      renderer.emphasis(
        list.map(contents, render_inline(_, references, renderer)),
        marker,
      )
    ast.StrongEmphasis(contents, marker) ->
      renderer.strong_emphasis(
        list.map(contents, render_inline(_, references, renderer)),
        marker,
      )
    ast.StrikeThrough(contents) ->
      renderer.strike_through(
        list.map(contents, render_inline(_, references, renderer)),
      )
    ast.Link(contents, title, href) ->
      renderer.link(
        list.map(contents, render_inline(_, references, renderer)),
        title,
        href,
      )
    ast.ReferenceLink(contents, ref) ->
      renderer.reference_link(
        list.map(contents, render_inline(_, references, renderer)),
        ref,
      )
    ast.Image(alt, title, href) -> renderer.image(alt, title, href)
    ast.ReferenceImage(alt, ref) -> renderer.reference_image(alt, ref)
    ast.UriAutolink(href) -> renderer.uri_autolink(href)
    ast.EmailAutolink(href) -> renderer.email_autolink(href)
    ast.HtmlInline(html) -> renderer.html_inline(html)
    ast.PlainText(contents) -> renderer.plain_text(contents)
    ast.HardLineBreak -> renderer.hard_line_break()
    ast.SoftLineBreak -> renderer.soft_line_break()
  }
}
