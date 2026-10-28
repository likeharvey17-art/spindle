# Product

Spindle: a native macOS desktop scene that turns whatever is playing into a record
on a turntable, drawn between the wallpaper and the desktop icons.

## Platform

macos

## Stack

Swift 6 (Swift 5 language mode), AppKit + Core Animation for the desktop scene,
SwiftUI for the menu-bar settings panel. Built with `build.sh` into
`/Applications/Spindle.app`. Menu-bar only (no Dock icon).

## Users

One person setting up their own Mac's desktop as a personal, ambient object: a
music listener who uses Spotify, Apple Music, Swinsian and browser players, and
cares about how their desktop looks. Visually demanding; rejects anything that
reads as generic or "AI-made".

## Product Purpose

Make listening visible and beautiful without asking for attention: the album art
lives on a photoreal sleeve and spinning record in a chosen scene, and nothing
on the desktop needs to be clicked.

## Positioning

Scenes are original photoreal images (Golden Hour, Lamplight, Overhead,
Midnight).

## Operating Context

The desktop scene runs all day behind work. The settings panel is opened rarely
from the menu bar: to switch scene, glance at what's playing, or change a
preference, then dismissed.

## Capabilities and Constraints

- Read-only access to playback: the app never sends play/pause/skip commands
  (they interfered with another controller app, Canopy).
- Must stay near-zero cost: steady spin runs as a Core Animation animation.
- Scene photos are user-generated (Nano Banana) and calibrated by JSON files in
  `~/Library/Application Support/Spindle/Scenes/`.

## Brand Commitments

Warm, tactile, analogue: walnut, brushed metal, paper, lamp light. Real
materials over flat UI. Settings panel direction (confirmed): a 1970s hi-fi
receiver faceplate. No generic app chrome, no tinted icon tiles, no default
toggles.

## Evidence on Hand

Four 4K scene images and user-generated material images for the panel (see the
panel brief).

## Product Principles

- The scene is the product; the panel serves it and should feel like part of
  the same room.
- Equal weight in the panel: now playing, scenes, settings.
- Never slow the Mac down.

## Accessibility & Inclusion

Panel controls keep real accessibility roles and values (toggles report on/off,
selectors report the selection), keyboard focus where macOS provides it, and
legible contrast on the engraved labels.
