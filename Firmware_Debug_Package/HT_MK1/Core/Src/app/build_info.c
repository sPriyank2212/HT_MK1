/**
  ******************************************************************************
  * @file    build_info.c
  * @brief   Build date/time stamp - see build_info.h.
  *
  *          Keep this file free of anything else: it is recompiled on every
  *          build (pre-build touch), so anything added here is rebuilt each
  *          time too.
  ******************************************************************************
  */
#include "app/build_info.h"

#include <stddef.h>

/* __DATE__ is "Mmm dd yyyy" with a SPACE-padded day ("Oct  2 2026");
 * __TIME__ is "hh:mm:ss". Both are fixed-width, so they are re-ordered into
 * ISO-8601 by position rather than parsed. */
static const char kDate[] = __DATE__;
static const char kTime[] = __TIME__;

static char s_stamp[BUILD_INFO_STAMP_LEN];

static char month_digit(char a, char b, char c, int digit_index)
{
  static const char kMonths[] = "JanFebMarAprMayJunJulAugSepOctNovDec";
  for (size_t m = 0U; m < 12U; m++)
  {
    const char *p = &kMonths[m * 3U];
    if (p[0] == a && p[1] == b && p[2] == c)
    {
      const unsigned n = (unsigned)m + 1U;
      return (char)('0' + (digit_index == 0 ? n / 10U : n % 10U));
    }
  }
  return '0'; /* unreachable for a conforming compiler */
}

const char *BuildInfo_Stamp(void)
{
  if (s_stamp[0] == '\0')
  {
    /* year */
    s_stamp[0]  = kDate[7];
    s_stamp[1]  = kDate[8];
    s_stamp[2]  = kDate[9];
    s_stamp[3]  = kDate[10];
    s_stamp[4]  = '-';
    /* month */
    s_stamp[5]  = month_digit(kDate[0], kDate[1], kDate[2], 0);
    s_stamp[6]  = month_digit(kDate[0], kDate[1], kDate[2], 1);
    s_stamp[7]  = '-';
    /* day (space-padded in __DATE__) */
    s_stamp[8]  = (kDate[4] == ' ') ? '0' : kDate[4];
    s_stamp[9]  = kDate[5];
    s_stamp[10] = 'T';
    /* time */
    s_stamp[11] = kTime[0];
    s_stamp[12] = kTime[1];
    s_stamp[13] = ':';
    s_stamp[14] = kTime[3];
    s_stamp[15] = kTime[4];
    s_stamp[16] = ':';
    s_stamp[17] = kTime[6];
    s_stamp[18] = kTime[7];
    s_stamp[19] = '\0';
  }
  return s_stamp;
}
