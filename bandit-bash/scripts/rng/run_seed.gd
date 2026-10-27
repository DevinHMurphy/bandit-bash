# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_seed.gd
# Author:
# Created:  October 27, 2026
# Modified: October 27, 2026
# ==============================================================================

class_name RunSeed
extends RefCounted
## The run seed every [RngStream] of a run is derived from: making one, and writing it for people.
##
## A seed is 0 to [constant MAX_SEED]. 52 bits fill exactly 13 hex digits and stay below 2^53, so
## [member CampaignData.run_seed] saves it as an exact JSON number (save-system.md, Data rules).
## [method format] is the text a bug report, a repro dump or a debug field names a seed by, and
## [method parse] reads it back.[br]
## [method generate] draws from the OS's secure random source, never from the global generator or
## a stream: the global generator is shared with cosmetic code, and no stream exists before the
## run has a seed.
##
## @tutorial(RNG streams plan): docs/plans/2026-10-26-rng-streams.md

## The largest run seed, 2^52 - 1.
const MAX_SEED: int = 0xFFFFFFFFFFFFF

## Not a seed: what [method parse] returns for text it can't read.
const NO_SEED: int = -1

# A formatted seed is 13 hex digits in groups of 4 from the left: 3F9A-12C0-77E1-A.
const _DIGITS: int = 13
const _GROUP_LENGTH: int = 4
const _SEPARATOR: String = "-"
const _HEX_DIGITS: String = "0123456789ABCDEF"

# Bytes read from the secure source: one u64, masked down to MAX_SEED.
const _ENTROPY_BYTES: int = 8


## A new random run seed, 0 to [constant MAX_SEED].
static func generate() -> int:
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(_ENTROPY_BYTES)
	return bytes.decode_u64(0) & MAX_SEED


## [param run_seed] as 13 uppercase hex digits in groups, e.g. [code]3F9A-12C0-77E1-A[/code].
## Returns an empty string, with an error, for a value outside 0 to [constant MAX_SEED].
static func format(run_seed: int) -> String:
	if run_seed < 0 or run_seed > MAX_SEED:
		push_error("RunSeed: not a run seed - %d" % [run_seed])
		return ""
	var digits: String = ("%X" % [run_seed]).lpad(_DIGITS, "0")
	var groups: PackedStringArray = []
	for start: int in range(0, _DIGITS, _GROUP_LENGTH):
		groups.append(digits.substr(start, _GROUP_LENGTH))
	return _SEPARATOR.join(groups)


## The seed [param text] names, as written by [method format], or [constant NO_SEED].
## Case, dashes and surrounding spaces don't matter; all 13 digits must be there.
static func parse(text: String) -> int:
	# Dashes may be anywhere or missing, but every digit is required: a seed cut short when copied
	# is refused rather than read as a different seed.
	var digits: String = text.strip_edges().replace(_SEPARATOR, "").to_upper()
	if digits.length() != _DIGITS:
		return NO_SEED
	for character: String in digits:
		if not _HEX_DIGITS.contains(character):
			return NO_SEED
	return digits.hex_to_int()
