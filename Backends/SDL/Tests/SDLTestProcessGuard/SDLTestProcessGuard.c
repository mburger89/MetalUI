#include "SDLTestProcessGuard.h"
int muitg_parse_deadline_seconds(const char *value) { (void)value; return 0; }
void muitg_watch_parent(pid_t original, int pollMilliseconds, void (*onOrphan)(void), void (*onPoll)(void)) { (void)original; (void)pollMilliseconds; (void)onOrphan; (void)onPoll; }
void muitg_start_deadline(int milliseconds, void (*onExpire)(void)) { (void)milliseconds; (void)onExpire; }
