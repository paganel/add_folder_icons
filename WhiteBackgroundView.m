//
//  WhiteBackgroundView.m
//  Add Folder Icons
//
//  An NSView subclass that simply fills itself with an opaque white colour.
//
//  Created by Andrew Hodgkinson on 26/05/2012.
//  Copyright (c) 2012 Hipposoft. All rights reserved.
//

#import "WhiteBackgroundView.h"

@implementation WhiteBackgroundView

- ( void ) drawRect: ( NSRect ) dirtyRect
{
    /* Simple and fast but doesn't allow translucency; if you want to add that,
     * see e.g.:
     *
     *   http://stackoverflow.com/questions/2962790/best-way-to-change-the-background-color-for-an-nsview
     */

    [ [ NSColor whiteColor ] setFill ];
    NSRectFill( dirtyRect );
}

@end
