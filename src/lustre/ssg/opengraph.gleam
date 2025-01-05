// IMPORTS ---------------------------------------------------------------------

import gleam/int
import gleam/uri
import lustre/attribute.{attribute}
import lustre/element/html

// ELEMENTS --------------------------------------------------------------------

pub fn title(text) {
  html.meta([attribute("property", "og:title"), attribute.content(text)])
}

pub fn website() {
  html.meta([attribute("property", "og:type"), attribute.content("website")])
}

pub fn url(content) {
  html.meta([
    attribute("property", "og:url"),
    attribute.content(uri.to_string(content)),
  ])
}

pub fn description(content) {
  html.meta([
    attribute("property", "og:description"),
    attribute.content(content),
  ])
}

pub fn site_name(content) {
  html.meta([attribute("property", "og:site_name"), attribute.content(content)])
}

pub fn image(content) {
  html.meta([
    attribute("property", "og:image"),
    attribute.content(uri.to_string(content)),
  ])
}

pub fn image_type(content) {
  html.meta([attribute("property", "og:image:type"), attribute.content(content)])
}

pub fn image_width(content) {
  html.meta([
    attribute("property", "og:image:width"),
    attribute.content(int.to_string(content)),
  ])
}

pub fn image_height(content) {
  html.meta([
    attribute("property", "og:image:height"),
    attribute.content(int.to_string(content)),
  ])
}

pub fn image_alt(content) {
  html.meta([attribute("property", "og:image:alt"), attribute.content(content)])
}
