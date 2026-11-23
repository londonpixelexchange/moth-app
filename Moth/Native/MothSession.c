// Copyright (c) 2026 Thomas Edward Vaughan, trading as London Pixel Exchange.
// SPDX-License-Identifier: LicenseRef-Moth-SAL-1.0
// Source-available under the Moth Source-Available Licence 1.0. See LICENSE.

#include "MothSession.h"
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <util.h>
#include <poll.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <arpa/inet.h>
#include <libkern/OSByteOrder.h>

// The helper, not the GUI, owns the PTY. A GUI disconnect never signals the shell.
// One authenticated local client at a time. All sockets and PTYs are close-on-exec.
// The bounded journal stores complete output and resize packets, in order.
#define JOURNAL_LIMIT (64u * 1024u * 1024u)
#define PACKET_LIMIT (1024u * 1024u)
typedef struct Packet { struct Packet *next; size_t size; unsigned char bytes[]; } Packet;
typedef struct { Packet *head, *tail; size_t size; int truncated; } Journal;
static Packet *packet(uint8_t type, const void *data, uint32_t size) {
    Packet *p = malloc(sizeof(*p) + size + 5);
    if (!p) return NULL;
    p->next = NULL; p->size = size + 5; p->bytes[0] = type;
    uint32_t n = htonl(size); memcpy(p->bytes + 1, &n, 4);
    if (size) memcpy(p->bytes + 5, data, size);
    return p;
}
static void journal_add(Journal *j, Packet *p) {
    if (!p) { j->truncated=1; return; }
    if (j->tail) j->tail->next = p; else j->head = p;
    j->tail = p; j->size += sizeof(*p)+p->size;
    while (j->size > JOURNAL_LIMIT && j->head != j->tail) {
        Packet *old = j->head; j->head = old->next; j->size -= sizeof(*old)+old->size; free(old); j->truncated = 1;
    }
}
static void private_socket(int fd) {
    fcntl(fd, F_SETFD, FD_CLOEXEC);
    int one = 1; setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
    struct timeval timeout = {2,0}; setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout));
}
static int address(struct sockaddr_un *addr, const char *path) {
    if (strlen(path) >= sizeof(addr->sun_path)) { errno = ENAMETOOLONG; return -1; }
    memset(addr,0,sizeof(*addr)); addr->sun_family = AF_UNIX; strlcpy(addr->sun_path,path,sizeof(addr->sun_path)); return 0;
}
static int connect_raw(const char *path) {
    struct sockaddr_un addr; if (address(&addr,path)) return -1;
    int fd = socket(AF_UNIX,SOCK_STREAM,0); if (fd < 0) return -1;
    private_socket(fd);
    if (connect(fd,(struct sockaddr *)&addr,sizeof(addr))) { close(fd); return -1; }
    uid_t uid; gid_t gid;
    if (getpeereid(fd,&uid,&gid) || uid != getuid()) { close(fd); errno = EACCES; return -1; }
    return fd;
}
int moth_session_connect(const char *path) {
    int fd=connect_raw(path); if (fd<0) return -1;
    if (moth_session_send(fd,'B',NULL,0)) { close(fd); return -1; }
    return fd;
}
int moth_session_end(const char *path) {
    int fd=connect_raw(path); if (fd<0) return -1;
    int result=moth_session_send(fd,'T',NULL,0); shutdown(fd,SHUT_WR); close(fd); return result;
}
static int write_all(int fd, const void *data, size_t count) {
    const unsigned char *bytes = data;
    while (count) { ssize_t n = write(fd,bytes,count); if (n < 0 && errno == EINTR) continue; if (n <= 0) return -1; bytes += n; count -= n; }
    return 0;
}
int moth_session_send(int fd, uint8_t type, const void *data, uint32_t count) {
    if (count > PACKET_LIMIT) { errno = EMSGSIZE; return -1; }
    Packet *p = packet(type,data,count); if (!p) return -1;
    int result = write_all(fd,p->bytes,p->size); free(p); return result;
}
static int send_status(int fd, uint8_t type, pid_t pid, pid_t foreground, int rows, int cols, int truncated) {
    uint32_t values[] = {htonl((uint32_t)pid),htonl((uint32_t)foreground),htonl(rows),htonl(cols),htonl(truncated)};
    return moth_session_send(fd,type,values,sizeof(values));
}
static int child_wake_fd = -1;
static void child_changed(int unused) {
    (void)unused; int saved=errno; unsigned char byte=1;
    if (child_wake_fd>=0) { ssize_t ignored=write(child_wake_fd,&byte,1); (void)ignored; }
    errno=saved;
}
static void end_shell(int master, pid_t child) {
    pid_t foreground = tcgetpgrp(master);
    if (foreground > 0 && foreground != getpgrp()) kill(-foreground,SIGHUP);
    kill(-child,SIGHUP); kill(child,SIGHUP);
}
int moth_session_broker(const char *path, int rows, int cols, const char *shell, char *const argv[]) {
    umask(0077); signal(SIGPIPE,SIG_IGN); signal(SIGHUP,SIG_IGN);
    if (setsid() < 0 && errno != EPERM) return 1;
    struct sockaddr_un addr; if (address(&addr,path)) return 2;
    int listener = socket(AF_UNIX,SOCK_STREAM,0); if (listener < 0) return 3;
    private_socket(listener);
    // Never unlink someone else's listening endpoint. Session paths are fresh UUIDs.
    if (bind(listener,(struct sockaddr *)&addr,sizeof(addr)) || chmod(path,0600) || listen(listener,2)) { close(listener); return 4; }
    int wake[2];
    if (pipe(wake)) { close(listener); unlink(path); return 5; }
    for (int i=0;i<2;i++) { fcntl(wake[i],F_SETFD,FD_CLOEXEC); fcntl(wake[i],F_SETFL,O_NONBLOCK); }
    child_wake_fd=wake[1]; signal(SIGCHLD,child_changed);
    int master = -1; struct winsize size = {.ws_row=rows,.ws_col=cols};
    pid_t child = forkpty(&master,NULL,NULL,&size);
    if (child < 0) { close(wake[0]); close(wake[1]); close(listener); unlink(path); return 5; }
    if (child == 0) {
        signal(SIGHUP,SIG_DFL); signal(SIGPIPE,SIG_DFL); signal(SIGCHLD,SIG_DFL); close(wake[0]); close(wake[1]);
        execv(shell,argv); _exit(127);
    }
    fcntl(master,F_SETFD,FD_CLOEXEC); fcntl(master,F_SETFL,O_NONBLOCK);
    int client = -1, reaped = 0, status = 0, eof = 0, explicit_close = 0, exit_sent = 0;
    time_t ended_at = 0;
    Journal journal = {0}; uint64_t sequence = 0, acknowledged = 0;
    unsigned char *input = malloc(PACKET_LIMIT + 5); size_t input_count = 0;
    unsigned char *pending = malloc(PACKET_LIMIT); size_t pending_count = 0, pending_offset = 0;
    if (!input || !pending) { end_shell(master,child); close(master); close(listener); close(wake[0]); close(wake[1]); unlink(path); free(input); free(pending); return 6; }
    while (1) {
        struct pollfd fds[] = {{listener,POLLIN,0},{eof ? -1 : master,POLLIN,0},{client,pending_count > pending_offset ? 0 : POLLIN,0},{wake[0],POLLIN,0}};
        if (pending_count > pending_offset) fds[1].events |= POLLOUT;
        int timeout=-1;
        if (reaped) { long remaining=86400-(time(NULL)-ended_at); timeout=remaining>0 ? (int)(remaining*1000) : 0; }
        int ready = poll(fds,4,timeout);
        if (fds[3].revents & POLLIN) { unsigned char bytes[64]; while (read(wake[0],bytes,sizeof(bytes))>0) {} }
        if (ready < 0 && errno != EINTR) break;
        if (fds[0].revents & POLLIN) {
            int next = accept(listener,NULL,NULL); uid_t uid; gid_t gid;
            if (next >= 0) {
                private_socket(next);
                if (client >= 0) {
                    unsigned char byte; ssize_t peek=recv(client,&byte,1,MSG_PEEK|MSG_DONTWAIT);
                    if (peek == 0 || (fds[2].revents & POLLHUP)) { close(client); client=-1; fds[2].revents=0; }
                }
                if (getpeereid(next,&uid,&gid) || uid != getuid()) close(next);
                else {
                    // A separate authenticated stop handshake avoids replaying megabytes just
                    // to close a disconnected session or discard an old recovery arrangement.
                    unsigned char hello[5]; struct timeval timeout={2,0};
                    setsockopt(next,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
                    ssize_t count=recv(next,hello,sizeof(hello),MSG_WAITALL);
                    if (count==5 && hello[0]=='T' && !hello[1] && !hello[2] && !hello[3] && !hello[4]) { close(next); explicit_close=1; break; }
                    if (count!=5 || hello[0]!='B' || hello[1] || hello[2] || hello[3] || hello[4] || client>=0) { close(next); continue; }
                    timeout.tv_sec=0; setsockopt(next,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
                    client = next; input_count = 0;
                    struct timeval replay_timeout={30,0}; setsockopt(client,SOL_SOCKET,SO_SNDTIMEO,&replay_timeout,sizeof(replay_timeout));
                    int ok = send_status(client,'H',child,tcgetpgrp(master),rows,cols,journal.truncated);
                    // Replay uses the original grid, then every recorded resize. Never reply to
                    // historical terminal queries or replay bells/clipboard writes in the GUI.
                    for (Packet *p=journal.head; !ok && p; p=p->next) {
                        uint8_t saved_type = p->bytes[0];
                        if (saved_type == 'O' && p->size >= 13) { uint64_t value; memcpy(&value,p->bytes+5,8); if (OSSwapBigToHostInt64(value) <= acknowledged) p->bytes[0]='P'; }
                        ok=write_all(client,p->bytes,p->size); p->bytes[0]=saved_type;
                    }
                    if (!ok) ok=moth_session_send(client,'E',NULL,0);
                    replay_timeout.tv_sec=2; setsockopt(client,SOL_SOCKET,SO_SNDTIMEO,&replay_timeout,sizeof(replay_timeout));
                    if (ok) { close(client); client=-1; }
                }
            }
        }
        if (client >= 0 && (fds[2].revents & (POLLIN|POLLHUP|POLLERR))) {
            ssize_t n = read(client,input+input_count,PACKET_LIMIT+5-input_count);
            if (n <= 0) { close(client); client=-1; input_count=0; }
            else {
                input_count += n;
                while (input_count >= 5) {
                    uint32_t count; memcpy(&count,input+1,4); count=ntohl(count);
                    if (count > PACKET_LIMIT) { close(client); client=-1; input_count=0; break; }
                    if (input_count < count+5) break;
                    if (input[0]=='I' && !eof && count <= PACKET_LIMIT-pending_count) { memcpy(pending+pending_count,input+5,count); pending_count+=count; }
                    else if (input[0]=='R' && (count==8 || count==16)) {
                        uint32_t values[4]={0}; memcpy(values,input+5,count);
                        int r=ntohl(values[0]),c=ntohl(values[1]);
                        if (r>=2 && r<=4096 && c>=2 && c<=4096) { size.ws_row=r; size.ws_col=c;
                            if (count==16) { size.ws_xpixel=(unsigned short)ntohl(values[2]); size.ws_ypixel=(unsigned short)ntohl(values[3]); }
                            ioctl(master,TIOCSWINSZ,&size); journal_add(&journal,packet('R',input+5,count)); }
                    } else if (input[0]=='A' && count==8) { uint64_t value; memcpy(&value,input+5,8); value=OSSwapBigToHostInt64(value); if (value<=sequence && value>acknowledged) acknowledged=value;
                    } else if (input[0]=='T' && count==0) { explicit_close=1; break; }
                    memmove(input,input+count+5,input_count-count-5); input_count-=count+5;
                }
            }
        }
        if (explicit_close) break;
        if (pending_count > pending_offset) {
            ssize_t n=write(master,pending+pending_offset,pending_count-pending_offset);
            if (n>0) pending_offset+=n;
            if (pending_offset==pending_count) pending_offset=pending_count=0;
        }
        if (!eof && (fds[1].revents & (POLLIN|POLLHUP|POLLERR))) {
            unsigned char output[65536]; ssize_t n=read(master,output,sizeof(output));
            if (n>0) {
                unsigned char framed[65536+8]; uint64_t value=OSSwapHostToBigInt64(++sequence);
                memcpy(framed,&value,8); memcpy(framed+8,output,n);
                journal_add(&journal,packet('O',framed,(uint32_t)n+8));
                if (client>=0 && moth_session_send(client,'O',framed,(uint32_t)n+8)) { close(client); client=-1; }
            } else if (n==0 || (n<0 && errno!=EAGAIN && errno!=EINTR)) eof=1;
        }
        if (!reaped && waitpid(child,&status,WNOHANG)==child) { reaped=1; ended_at=time(NULL); }
        if (reaped && eof && client>=0 && !exit_sent) { uint32_t value=htonl(WIFEXITED(status) ? WEXITSTATUS(status) : 128+WTERMSIG(status)); moth_session_send(client,'X',&value,4); exit_sent=1; }
        // Keep the read half open until the GUI consumes the final output/status.
        // Closing immediately races its output ACKs and can discard the buffered exit packet.
        if (exit_sent && client<0) break;
        // A crashed GUI may be reopened later. Completed sessions remain recoverable for
        // a day; live detached sessions have no artificial time limit.
        if (reaped && time(NULL)-ended_at>86400) break;
    }
    if (explicit_close || !reaped) end_shell(master,child);
    close(master); if (client>=0) close(client); close(listener); child_wake_fd=-1; close(wake[0]); close(wake[1]); unlink(path);
    if (!reaped) { for (int i=0;i<20;i++) { if (waitpid(child,&status,WNOHANG)==child) { reaped=1; break; } usleep(10000); } if (!reaped) { kill(-child,SIGKILL); kill(child,SIGKILL); waitpid(child,&status,0); } }
    while (journal.head) { Packet *p=journal.head; journal.head=p->next; free(p); }
    free(input); free(pending); return 0;
}
