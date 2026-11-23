// Copyright (c) 2026 Thomas Edward Vaughan, trading as London Pixel Exchange.
// SPDX-License-Identifier: LicenseRef-Moth-SAL-1.0
// Source-available under the Moth Source-Available Licence 1.0. See LICENSE.

#ifndef MOTH_SESSION_H
#define MOTH_SESSION_H
#include <stdint.h>
// Framed, local-only PTY transport. No shell command strings cross this boundary.
int moth_session_broker(const char *socket_path, int rows, int cols, const char *shell, char *const argv[]);
int moth_session_connect(const char *socket_path);
int moth_session_end(const char *socket_path);
int moth_session_send(int fd, uint8_t type, const void *bytes, uint32_t count);
#endif
