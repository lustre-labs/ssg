// IMPORTS ---------------------------------------------------------------------

import lustre/attribute.{type Attribute, attribute}
import lustre/element.{type Element, element}

// ELEMENTS --------------------------------------------------------------------

pub fn feed(attrs: List(Attribute(a)), children: List(Element(a))) {
  element(
    "feed",
    [attribute("xmlns", "http://www.w3.org/2005/Atom"), ..attrs],
    children,
  )
}

pub fn entry(attrs: List(Attribute(a)), children: List(Element(a))) {
  element("entry", attrs, children)
}

pub fn id(attrs: List(Attribute(a)), uri: String) {
  element("id", attrs, [element.text(uri)])
}

pub fn title(attrs: List(Attribute(a)), title: String) {
  element("title", [attribute("type", "html"), ..attrs], [element.text(title)])
}

pub fn updated(attrs: List(Attribute(a)), iso_timestamp: String) {
  element("updated", attrs, [element.text(iso_timestamp)])
}

pub fn published(attrs: List(Attribute(a)), iso_timestamp: String) {
  element("published", attrs, [element.text(iso_timestamp)])
}

pub fn author(attrs: List(Attribute(a)), children: List(Element(a))) {
  element("author", attrs, children)
}

pub fn contributor(attrs: List(Attribute(a)), children: List(Element(a))) {
  element("contributor", attrs, children)
}

pub fn source(attrs: List(Attribute(a)), children: List(Element(a))) {
  element("source", attrs, children)
}

pub fn link(attrs: List(attribute.Attribute(a))) {
  element.advanced("", "link", attrs, [], True, False)
}

pub fn name(attrs: List(Attribute(a)), name: String) {
  element("name", attrs, [element.text(name)])
}

pub fn email(attrs: List(Attribute(a)), email: String) {
  element("email", attrs, [element.text(email)])
}

pub fn uri(attrs: List(Attribute(a)), uri: String) {
  element("uri", attrs, [element.text(uri)])
}

pub fn category(attrs: List(Attribute(a))) {
  element.advanced("", "category", attrs, [], True, False)
}

pub fn generator(attrs: List(Attribute(a)), name: String) {
  element("generator", attrs, [element.text(name)])
}

pub fn icon(attrs: List(Attribute(a)), path: String) {
  element("icon", attrs, [element.text(path)])
}

pub fn logo(attrs: List(Attribute(a)), path: String) {
  element("logo", attrs, [element.text(path)])
}

pub fn rights(attrs: List(Attribute(a)), rights: String) {
  element("rights", attrs, [element.text(rights)])
}

pub fn subtitle(attrs: List(Attribute(a)), subtitle: String) {
  element("subtitle", [attribute("type", "html"), ..attrs], [
    element.text(subtitle),
  ])
}

pub fn summary(attrs: List(Attribute(a)), summary: String) {
  element("summary", [attribute("type", "html"), ..attrs], [
    element.text(summary),
  ])
}

pub fn content(attrs: List(Attribute(a)), content: String) {
  element("content", [attribute("type", "html"), ..attrs], [
    element.text(content),
  ])
}
