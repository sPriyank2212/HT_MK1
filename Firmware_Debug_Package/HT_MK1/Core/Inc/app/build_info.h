/**
  ******************************************************************************
  * @file    build_info.h
  * @brief   When this firmware image was built.
  *
  *          The stamp is the build PC's own clock, captured by the compiler
  *          (__DATE__ / __TIME__) - there is no RTC involved and nothing is
  *          set at run time. It is reported to the GUI in the >ID reply
  *          ("build=YYYY-MM-DDTHH:MM:SS") so a unit can be matched to the
  *          build it is running.
  *
  *          build_info.c is "touched" by a pre-build step (see the
  *          configuration's Pre-build steps in .cproject) so it is recompiled
  *          on EVERY build; otherwise an incremental build that did not edit
  *          that file would carry an old stamp.
  ******************************************************************************
  */
#ifndef APP_BUILD_INFO_H
#define APP_BUILD_INFO_H

#ifdef __cplusplus
extern "C" {
#endif

/** Length of the stamp including the terminating NUL: "2026-10-22T18:30:12". */
#define BUILD_INFO_STAMP_LEN  20U

/**
  * @brief  Build date and time as "YYYY-MM-DDTHH:MM:SS" (local time of the
  *         PC that compiled this image).
  * @retval Pointer to a static NUL-terminated string; never NULL.
  */
const char *BuildInfo_Stamp(void);

#ifdef __cplusplus
}
#endif

#endif /* APP_BUILD_INFO_H */
