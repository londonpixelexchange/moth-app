// Copyright (c) 2026 T E Vaughan.
// SPDX-License-Identifier: LicenseRef-Moth-SAL-1.0
// Source-available under the Moth Source-Available Licence 1.0. See LICENSE.

#include "MothEncoding.h"
#include <iconv.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <errno.h>
#include <stdint.h>
struct MothCodec { iconv_t handle; uint8_t pending[16]; size_t pending_count; int replace_invalid; };
MothCodec *moth_codec_create(const char *from, const char *to, int replace_invalid) {
    // Windows-compatible Shift JIS preserves ASCII backslash and tilde,
    // which are terminal protocol bytes as well as visible characters.
    if (strcasecmp(from,"SHIFT_JIS") == 0) from = "CP932";
    if (strcasecmp(to,"SHIFT_JIS") == 0) to = "CP932";
    iconv_t handle = iconv_open(to, from);
    if (handle == (iconv_t)-1) return NULL;
    MothCodec *codec = calloc(1, sizeof(*codec));
    if (!codec) { iconv_close(handle); return NULL; }
    codec->handle = handle; codec->replace_invalid = replace_invalid; return codec;
}
void moth_codec_destroy(MothCodec *codec) { if (codec) { iconv_close(codec->handle); free(codec); } }
int moth_codec_supported(const char *encoding) {
    MothCodec *a = moth_codec_create(encoding, "UTF-8", 1), *b = moth_codec_create("UTF-8", encoding, 0);
    int valid = a && b; moth_codec_destroy(a); moth_codec_destroy(b); return valid;
}
int moth_codec_convert(MothCodec *codec, const uint8_t *input, size_t length, int final,
                       uint8_t **output, size_t *output_length) {
    *output = NULL; *output_length = 0;
    if (!codec || length > SIZE_MAX/8-128) return -1;
    size_t total = codec->pending_count + length, capacity = total*8 + 128;
    uint8_t *joined = malloc(total ? total : 1), *result = malloc(capacity);
    if (!joined || !result) { free(joined); free(result); return -1; }
    memcpy(joined, codec->pending, codec->pending_count);
    if (length) memcpy(joined+codec->pending_count, input, length);
    codec->pending_count = 0;
    char *source = (char *)joined, *destination = (char *)result;
    size_t remaining = total, available = capacity;
    while (remaining) {
        size_t converted = iconv(codec->handle, &source, &remaining, &destination, &available);
        if (converted != (size_t)-1) continue;
        if (errno == E2BIG) {
            size_t used = (size_t)(destination-(char *)result);
            if (capacity > SIZE_MAX/2) goto failed;
            capacity *= 2; uint8_t *grown = realloc(result, capacity);
            if (!grown) goto failed;
            result = grown; destination = (char *)result+used; available = capacity-used; continue;
        }
        if (errno == EINVAL && !final && remaining <= sizeof(codec->pending)) {
            memcpy(codec->pending, source, remaining); codec->pending_count = remaining; remaining = 0; break;
        }
        if (!codec->replace_invalid || available < 3) goto failed;
        // Output decoding uses U+FFFD for malformed bytes; never silently discard input.
        *destination++ = (char)0xEF; *destination++ = (char)0xBF; *destination++ = (char)0xBD; available -= 3;
        source++; remaining--;
    }
    if (final && iconv(codec->handle, NULL, NULL, &destination, &available) == (size_t)-1) goto failed;
    free(joined); *output = result; *output_length = (size_t)(destination-(char *)result); return 0;
failed:
    free(joined); free(result); return -1;
}
