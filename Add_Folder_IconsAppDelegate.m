//
//  Add_Folder_IconsAppDelegate.m
//  Add Folder Icons
//
//  Created by Andrew Hodgkinson on 14/03/2010.
//  Copyright 2010, 2011 Hipposoft. All rights reserved.
//

#import "Add_Folder_IconsAppDelegate.h"
#import "ApplicationSupport.h"
#import "SlipCoverSupport.h"
#import "GlobalConstants.h"
#import "GlobalSemaphore.h"

@implementation Add_Folder_IconsAppDelegate

#ifdef UPDATABLE
    @synthesize updateHelper;
#endif

- ( void ) applicationDidFinishLaunching: ( NSNotification * ) aNotification
{
    /* The icon generator needs the global semaphore system */

    globalSemaphoreInit();

    /* Possibly wake up the update mechanism */

    #ifdef UPDATABLE
        updateHelper = [ [ UpdateHelper alloc ] init ];
        [ mainMenuController addUpdaterMenuEntriesWith: updateHelper ];
    #endif

    /* Get hold of the singleton icon style manager instance */

    iconStyleManager = [ IconStyleManager iconStyleManager ];

    /* Establish various defaults, allocate singletons */

    [ self establishDefaultPreferences ];
    [ self standardFolderIcon          ];

    /* Create the main window, which opens itself */

    mainWindowController =
    [
        [ MainWindowController alloc ] initWithWindowNibName: MAIN_WINDOW_CONTROLLER_NIB_NAME
    ];

    /* Create the splash window, which opens above the main window */

    NSUserDefaults * defaults      = [ NSUserDefaults standardUserDefaults ];
    NSString       * showSplashKey = @"showSplashScreenAtStartup";

    if ( [ defaults boolForKey: showSplashKey ] != NO )
    {
        splashWindowController =
        [
            [ SplashWindowController alloc ] initWithWindowNibName: SPLASH_WINDOW_CONTROLLER_NIB_NAME
        ];
    }
}

- ( BOOL ) applicationShouldTerminateAfterLastWindowClosed: ( NSApplication * ) theApplication
{
    return YES;
}

/******************************************************************************\
 * -establishDefaultPreferences
 *
 * Set up the default preferences and register them. Since preferences include
 * a record of default style, the preset styles must be set up first.
 *
 * See also: -establishDefaultIconStyles (IconStyleManager)
\******************************************************************************/

- ( void ) establishDefaultPreferences
{
    NSUserDefaults * userDefaults      = [ NSUserDefaults standardUserDefaults ];
    NSArray        * coverArtFilenames =
    @[
        @{ @"leafname": @"folder" },
        @{ @"leafname": @"cover"  }
    ];

    /* A fiddly bit - fetch a default style object and transform it into a
     * value which can be stored in the defaults dictionary in a manner
     * compatible with the bindings for the companion preferences GUI.
     */

    IconStyle * foundStyle     = [ iconStyleManager findClassicIconStyle ];
    NSString  * defaultStyleID =
    [
        [ [ foundStyle objectID ] URIRepresentation ] absoluteString
    ];

    /* Combine all the above to construct and register the defaults */

    NSDictionary * appDefaults =
    @{
        @"showSplashScreenAtStartup":    @YES,
        @"addSubFolders":                @NO,
        @"emptyListIfSuccessful":        @NO,
        @"colourLabelsIndicateCoverArt": @YES,
        @"coverArtFilenames":            coverArtFilenames,
        @"defaultStyle":                 defaultStyleID
    };

    [ userDefaults registerDefaults: appDefaults ];
}

/******************************************************************************\
 * -standardFolderIcon
 *
 * Ask the system for a generic folder icon and generate a CGImage variant of
 * it at CANVAS_SIZE x CANVAS_SIZE dimensions (see "GlobalConstants.h"). This
 * is only done once - the representation is then kept forever.
 *
 * Out: CGImageRef pointing to a CGImage version of the standard system folder
 *      icon. DO NOT EVER CALL 'release()' ON THIS.
\******************************************************************************/

- ( CGImageRef ) standardFolderIcon
{
    static dispatch_once_t onceToken;
    static CGImageRef      folderIconRef = NULL;

    dispatch_once( &onceToken, ^{

        NSImage * folder = [ NSImage imageNamed: NSImageNameFolder ];

        if ( folder )
        {
            /* To turn into a CGImage, just try to fill the canvas with the folder
             * icon. The OS selects the best image.
             *
             * We *DO NOT* adjust the requested size for retina DPI. The OS does
             * that internally, it seems; at least on OS X 10.11, requesting an
             * adjusted 512 for high DPI and thus asking for 1024, results in a
             * failure to fetch an image and a logged complaint from
             * iconservicesagent about being able to find a 2048x2048 image.
             */

            NSInteger  canvasSize = CANVAS_SIZE; /* (was 'dpiValue( CANVAS_SIZE )' */
            NSRect     imageRect  = NSMakeRect( 0, 0, canvasSize, canvasSize );
            CGImageRef localRef   =
            [
                folder CGImageForProposedRect: &imageRect
                                      context: nil
                                        hints: nil
            ];

            /* The above is owned by the NSImage and when the NSImage goes, the
             * folder goes with it. We need to store a copy.
             */

            if ( localRef )
            {
                folderIconRef = CGImageCreateCopy( localRef );
            }
        }

    } );

    return folderIconRef;
}

/******************************************************************************\
 * -showPreferences:
 *
 * Show the Preferences dialogue box. The preferences handler code deals with
 * restoring previous state.
\******************************************************************************/

- ( IBAction ) showPreferences: ( id ) sender
{
    ApplicationSpecificPreferencesWindowController * prefs =
    [
        ApplicationSpecificPreferencesWindowController applicationSpecificPreferencesWindowController
    ];

    [ prefs showWindow: sender ];
}

/******************************************************************************\
 * -showManageStyles:
 *
 * Show the Manage Styles dialogue box.
\******************************************************************************/

- ( IBAction ) showManageStyles: ( id ) sender
{
    if ( manageStylesWindowController == nil )
    {
        manageStylesWindowController =
        [
            [ ManageStylesWindowController alloc ] initWithWindowNibName: MANAGE_STYLES_CONTROLLER_NIB_NAME
        ];
    }

    [ manageStylesWindowController showWindow: sender ];
}

/******************************************************************************\
 * -applicationShouldTerminate:
 *
 * NSApplicationDelegate: Boilerplate Core Data material generated by Interface
 * Builder 3.2.5.
 *
 * Handle the saving of changes in the application managed object context
 * before the application terminates.
 *
 * In:  ( NSApplication * ) sender
 *      Application which is shutting down (i.e. this one) - used to present
 *      errors if problems are encountered during execution.
 *
 * Out: ( NSApplicationTerminateReply )
 *      Either "NSTerminateNow" to allow termination or "NSTerminateCancel" to
 *      prevent it.
\******************************************************************************/

- ( NSApplicationTerminateReply ) applicationShouldTerminate: ( NSApplication * ) sender
{
    NSManagedObjectContext * moc = [ iconStyleManager managedObjectContext ];
    if ( ! moc ) return NSTerminateNow;

    /* Belt and braces; the way the application uses CoreData means there
     * should be no edits to commit, but it doesn't hurt to make the call
     * just in case some unexpected condition left changes pending.
     */

    if ( ! [ moc commitEditing ] )
    {
        NSLog( @"%@:%s unable to commit editing to terminate", [ self class ], sel_getName( _cmd ) );
        return NSTerminateCancel;
    }

    if ( ! [ moc hasChanges ] ) return NSTerminateNow;

    NSError * error = nil;

    if ( ! [ moc save: &error ] )
    {
        /* This error handling simply presents error information in a panel with 
         * an "OK" button, which does not include any attempt at error recovery.
         * As a result, this implementation will present the information to the
         * user and then follow up with a panel asking if the user wishes to
         * "Quit Anyway", without saving the changes.
         *
         * Typically, this process should be altered to include application-
         * specific recovery steps. In the case of Add Folder Icons, there is
         * not much we can do to recover anyway.
         */

        BOOL result = [ sender presentError: error ];
        if ( result ) return NSTerminateCancel;

        NSString * question     = NSLocalizedString( @"Could not save Style changes while quitting. Quit anyway?",                              @"Quit without saves error question message" );
        NSString * info         = NSLocalizedString( @"Quitting now will lose any Style changes you have made since the last successful save.", @"Quit without saves error question info"    );
        NSString * quitButton   = NSLocalizedString( @"Quit Anyway",                                                                            @"Quit anyway button title"                  );
        NSString * cancelButton = NSLocalizedString( @"Cancel",                                                                                 @"Cancel button title"                       );
        NSAlert  * alert        = [ [ NSAlert alloc ] init ];

        [ alert setMessageText:     question     ];
        [ alert setInformativeText: info         ];
        [ alert addButtonWithTitle: quitButton   ];
        [ alert addButtonWithTitle: cancelButton ];

        NSInteger answer = [ alert runModal ];
        alert = nil;
        
        if ( answer == NSAlertSecondButtonReturn ) return NSTerminateCancel;
    }

    return NSTerminateNow;
}

@end
