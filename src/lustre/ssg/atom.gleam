// IMPORTS ---------------------------------------------------------------------

import lustre/attribute.{attribute}
import lustre/element.{type Element, element}

// ELEMENTS --------------------------------------------------------------------

pub fn feed(children: List(Element(a))) {
  element("feed", [attribute("xmlns", "http://www.w3.org/2005/Atom")], children)
}

pub fn entry(children: List(Element(a))) {
  element("entry", [], children)
}

pub fn id(uri: String) {
  element("id", [], [element.text(uri)])
}

pub fn title(title: String) {
  element("title", [attribute("type", "html")], [element.text(title)])
}

pub fn updated(iso_timestamp: String) {
  element("updated", [], [element.text(iso_timestamp)])
}

pub fn published(iso_timestamp: String) {
  element("published", [], [element.text(iso_timestamp)])
}

pub fn author(children: List(Element(a))) {
  element("author", [], children)
}

pub fn contributor(children: List(Element(a))) {
  element("contributor", [], children)
}

pub fn source(children: List(Element(a))) {
  element("source", [], children)
}

pub fn link(attributes: List(attribute.Attribute(a))) {
  element.advanced("", "link", attributes, [], True, False)
}

pub fn name(name: String) {
  element("name", [], [element.text(name)])
}

pub fn email(email: String) {
  element("email", [], [element.text(email)])
}

pub fn uri(uri: String) {
  element("uri", [], [element.text(uri)])
}

pub fn category(attributes: List(attribute.Attribute(a))) {
  element.advanced("", "category", attributes, [], True, False)
}

pub fn generator(attributes: List(attribute.Attribute(a)), name: String) {
  element("generator", attributes, [element.text(name)])
}

pub fn icon(path: String) {
  element("icon", [], [element.text(path)])
}

pub fn logo(path: String) {
  element("logo", [], [element.text(path)])
}

pub fn rights(rights: String) {
  element("rights", [], [element.text(rights)])
}

pub fn subtitle(subtitle: String) {
  element("subtitle", [attribute("type", "html")], [element.text(subtitle)])
}

pub fn summary(summary: String) {
  element("summary", [attribute("type", "html")], [element.text(summary)])
}

pub fn content(content: String) {
  element("content", [attribute("type", "html")], [element.text(content)])
}
