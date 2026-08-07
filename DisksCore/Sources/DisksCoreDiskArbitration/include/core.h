//
//  core.h
//  Disks
//
//  Created by Kyle Erhabor on 8/2/26.
//

#ifndef core_h
#define core_h

#include <mach/error.h>

static inline int disks_da_err_get_code(mach_error_t err) {
  return err_get_code(err);
}

#endif /* core_h */
