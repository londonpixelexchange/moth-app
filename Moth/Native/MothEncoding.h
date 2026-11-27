// Copyright (c) 2026 T E Vaughan.
// SPDX-License-Identifier: GPL-3.0-or-later
// Licensed under GNU GPL version 3 or later. See LICENSE.

#ifndef MOTH_ENCODING_H
#define MOTH_ENCODING_H
#include <stddef.h>
#include <stdint.h>
typedef struct MothCodec MothCodec;
MothCodec *moth_codec_create(const char *from, const char *to, int replace_invalid);
void moth_codec_destroy(MothCodec *codec);
int moth_codec_supported(const char *encoding);
int moth_codec_convert(MothCodec *codec, const uint8_t *input, size_t length, int final,
                       uint8_t **output, size_t *output_length);
#endif
