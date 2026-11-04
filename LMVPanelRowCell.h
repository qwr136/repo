#pragma once

#import <UIKit/UIKit.h>

// 5.32: the settings page and the floating panel used to draw rows two different
// ways - the settings page through LMVPSettingCell, the panel through a stock
// UITableViewCellStyleSubtitle. The stock cell puts the title at the top of the
// row and the subtitle at the bottom, so a 66pt row opened a gap between the two
// lines and the accessory view sat on the gap instead of on the title.
//
// This class is the shared skeleton: 17pt title over a 13pt subtitle, both
// starting at the same 16pt margin, and the accessory view centred on the TITLE
// line. Callers keep using -textLabel / -detailTextLabel / -accessoryView the way
// they always did; only the geometry moved in here.
@interface LMVPanelRowCell : UITableViewCell
@end
