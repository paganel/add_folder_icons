//
//  IconStyleManager.m
//  Add Folder Icons
//
//  Created by Andrew Hodgkinson on 24/01/2011.
//  Copyright 2011 Hipposoft. All rights reserved.
//
//  Always use "+iconStyleManager" to obtain references to instances of this
//  class.
//

#import "IconStyleManager.h"
#import "IconStyle.h"
#import "ApplicationSupport.h"
#import "SlipCoverSupport.h"

@implementation IconStyleManager

@synthesize persistentStoreCoordinator,
            managedObjectContext,
            managedObjectModel,
            slipCoverDefinitions;

/******************************************************************************\
 * +iconStyleManager
 *
 * Obtain a reference to a singleton instance of the icon style manager,
 * creating and initialising that object in passing if required. Always use
 * this method to obtain references to the icon style manager.
 *
 * Out: ( id )
 *      Value of "self".
\******************************************************************************/

static IconStyleManager * iconStyleManagerSingletonInstance = nil;

+ ( IconStyleManager * ) iconStyleManager
{
    if ( iconStyleManagerSingletonInstance == nil )
    {
        iconStyleManagerSingletonInstance = [ [ self alloc ] init ];
    }

    return iconStyleManagerSingletonInstance;
}

/******************************************************************************\
 * -init
 *
 * Initialise the icon style manager, waking up CoreData and making sure that
 * the basic presets are estabilshed in the database in passing.
 *
 * Do not manually "alloc" an instance of the style manager and then call here.
 * Instead, always use "+iconStyleManager".
 *
 * Out: ( id )
 *      Value of "self".
\******************************************************************************/

- ( instancetype ) init
{
    if ( ( self = [ super init ] ) )
    {
        /* Register the CoreData managed object ID <=> string value transformer
         * and tell it about the persistent store coordinator so it can do its
         * work.
         */

        coreDataObjectIDTransformer = [ [ CoreDataObjectIDTransformer alloc ] init ];
        [ NSValueTransformer setValueTransformer: coreDataObjectIDTransformer
                                         forName: CORE_DATA_OBJECT_ID_TRANSFORMER_NAME ];

        [ coreDataObjectIDTransformer setPersistentStoreCoordinator: [ self persistentStoreCoordinator ] ];

        /* Make sure the presets are set up */

        [ self establishPresetIconStyles ];

        /* Construct SlipCover case definitions and in passing make sure that
         * all existing icon styles are valid.
         */

        [ self checkIconStylesForValidity ];

        /* Watch SlipCover paths to make sure definitions don't change */

        NSMutableArray * watchPaths = [ SlipCoverSupport searchPathsForCovers ];

        if ( watchPaths != nil )
        {
            slipCoverCaseFolderWatcher = [ [ SCEvents alloc ] init ];
            [ slipCoverCaseFolderWatcher setDelegate: self ];
            [ slipCoverCaseFolderWatcher startWatchingPaths: watchPaths ];
        }
    }

    return self;
}

- ( void ) dealloc
{
    [ slipCoverCaseFolderWatcher stopWatchingPaths ];
}

/******************************************************************************\
 * -managedObjectModel
 *
 * Boilerplate Core Data material generated by Interface Builder 3.2.5.
 *
 * Creates, retains and returns the managed object model for the application 
 * by merging all of the models found in the application bundle.
\******************************************************************************/

- ( NSManagedObjectModel * ) managedObjectModel
{
    if ( managedObjectModel ) return managedObjectModel;
	
    managedObjectModel = [ NSManagedObjectModel mergedModelFromBundles: nil ];    
    return managedObjectModel;
}

/******************************************************************************\
 * -persistentStoreCoordinator
 *
 * Boilerplate Core Data material generated by Interface Builder 3.2.5.
 *
 * Returns the persistent store coordinator for the application. This 
 * implementation will create and return a coordinator, having added the 
 * store for the application to it. The directory for the store is created,
 * if necessary.
\******************************************************************************/

- ( NSPersistentStoreCoordinator * ) persistentStoreCoordinator
{
    if ( persistentStoreCoordinator ) return persistentStoreCoordinator;

    NSManagedObjectModel * mom = [ self managedObjectModel ];

    if ( ! mom )
    {
        NSAssert( NO, @"Managed Object Model is nil" );
        NSLog ( @"%@:%s No model to generate a store from", [ self class ], sel_getName( _cmd ) );
        return nil;
    }

    NSFileManager * fileManager                 = [ NSFileManager      defaultManager              ];
    NSString      * applicationSupportDirectory = [ ApplicationSupport applicationSupportDirectory ];
    NSError       * error                       = nil;
    
    if ( ! [ fileManager fileExistsAtPath: applicationSupportDirectory isDirectory: NULL] )
    {
		if ( ! [ fileManager createDirectoryAtPath: applicationSupportDirectory withIntermediateDirectories: NO attributes: nil error: &error ] )
        {
            NSAssert(
                NO,
                (
                    [
                        NSString stringWithFormat: @"Failed to create Application Support directory %@ : %@",
                                                   applicationSupportDirectory,
                                                   error 
                    ]
                )
            );

            NSLog( @"Error creating Application Support directory at %@ : %@", applicationSupportDirectory, error );
            return nil;
		}
    }

    NSURL * url = [ NSURL fileURLWithPath: [ applicationSupportDirectory stringByAppendingPathComponent: CORE_DATA_STORE_FILENAME ] ];
    persistentStoreCoordinator = [ [ NSPersistentStoreCoordinator alloc ] initWithManagedObjectModel: mom ];

    if ( ! [ persistentStoreCoordinator addPersistentStoreWithType: NSXMLStoreType 
                                                     configuration: nil 
                                                               URL: url 
                                                           options: nil 
                                                             error: &error ] )
    {
        [ NSApp presentError: error ];
        persistentStoreCoordinator = nil;
        return nil;
    }

    return persistentStoreCoordinator;
}

/******************************************************************************\
 * -managedObjectContext
 *
 * Boilerplate Core Data material generated by Interface Builder 3.2.5.
 *
 * Returns the managed object context for the application (which is already
 * bound to the persistent store coordinator for the application.) 
\******************************************************************************/

- ( NSManagedObjectContext * ) managedObjectContext
{
    if ( managedObjectContext ) return managedObjectContext;

    NSPersistentStoreCoordinator * coordinator = [ self persistentStoreCoordinator ];

    if ( ! coordinator )
    {
        NSMutableDictionary * dict = [ NSMutableDictionary dictionary ];

        [ dict setValue: @"Failed to initialize the styles store"         forKey: NSLocalizedDescriptionKey        ];
        [ dict setValue: @"There was an error building up the data file." forKey: NSLocalizedFailureReasonErrorKey ];

        NSError * error = [ NSError errorWithDomain: @"UkOrgPondAddFolderIconsErrorDomain" code: 9999 userInfo: dict ];
        [ NSApp presentError: error ];
        return nil;
    }

    managedObjectContext = [ [ NSManagedObjectContext alloc ] init ];
    [ managedObjectContext setPersistentStoreCoordinator: coordinator ];

    return managedObjectContext;
}

/******************************************************************************\
 * -establishDefaultIconStyles
 *
 * Set up the default collection of preset icon styles if the database is
 * empty, else leaves it alone.
 *
 * Called from "-init", so other instance methods can rely on the presets being
 * present in the database.
\******************************************************************************/

- ( void ) establishPresetIconStyles
{
    NSManagedObjectContext * moc         = [ self managedObjectContext ];
    NSManagedObjectModel   * mom         = [ self managedObjectModel   ];
    NSEntityDescription    * styleEntity = [ mom entitiesByName ][ @"IconStyle" ];
    IconStyle              * newStyle;

    /* Is the icon style collection empty? */
    
    NSError        * error   = nil;
    NSFetchRequest * request = [ [ NSFetchRequest alloc ] init ];

    [ request setEntity:              styleEntity ];
    [ request setIncludesSubentities: NO          ];

    NSUInteger count = [ moc countForFetchRequest: request error: &error ];
    

    /* Early exit points */

    if ( error != nil )
    {
        [ NSApp presentError: error ];
        return;
    }
    else if ( count != 0 )
    {
        return;
    }

    /* Convenience... */

    NSNumber * numYes = @YES;
    NSNumber * numNo  = @NO;

    /* "Preset: Classic thumbnails" - defaults are mostly fine */

    newStyle = [ [ IconStyle alloc ] initWithEntity: styleEntity
                       insertIntoManagedObjectContext: moc ];

    [ newStyle setIsPreset:      numYes ];
    [ newStyle setUsesSlipCover: numNo  ];
    [ newStyle setCreatedAt:     [ NSDate date ] ];
    [ newStyle setName:          DEFAULT_ICON_STYLE_NAME ];

    /* "Preset: Square covers (e.g. CDs) - a few more changes */

    newStyle = [ [ IconStyle alloc ] initWithEntity: styleEntity
                       insertIntoManagedObjectContext: moc ];

    [ newStyle setIsPreset:      numYes ];
    [ newStyle setUsesSlipCover: numNo  ];
    [ newStyle setCreatedAt:     [ NSDate date ] ];
    [ newStyle setName:          NSLocalizedString( @"Preset: Square covers (e.g. CDs)", @"Name of 'CD cover' preset icon style" ) ];

    [ newStyle setWhiteBackground: numNo  ];
    [ newStyle setRandomRotation:  numNo  ];
    [ newStyle setOnlyUseCoverArt: numYes ];
    [ newStyle setShowFolderInBackground: @( StyleShowFolderInBackgroundNever ) ];

    /* "Preset: Rectangular covers (e.g. DVDs) - the most changes */

    newStyle = [ [ IconStyle alloc ] initWithEntity: styleEntity
                       insertIntoManagedObjectContext: moc ];

    [ newStyle setIsPreset:      numYes ];
    [ newStyle setUsesSlipCover: numNo  ];
    [ newStyle setCreatedAt:     [ NSDate date ] ];
    [ newStyle setName:          NSLocalizedString( @"Preset: Rectangular covers (e.g. DVDs)", @"Name of 'DVD cover' preset icon style" ) ];

    [ newStyle setCropToSquare:    numNo  ];
    [ newStyle setWhiteBackground: numNo  ];
    [ newStyle setRandomRotation:  numNo  ];
    [ newStyle setOnlyUseCoverArt: numYes ];
    [ newStyle setShowFolderInBackground: @( StyleShowFolderInBackgroundNever ) ];

    /* Save the presets */

    error = nil;
    if ( ! [ moc save: &error ] ) [ NSApp presentError: error ];
}

/******************************************************************************\
 * -findSlipCoverStyles
 *
 * Returns an array of Icon Style objects which all use SlipCover case designs.
 * If an error occurs internally, it is reported and 'nil' will be returned.
 *
 * Out: ( NSArray * )
 *      Autoreleased array of pointers to IconStyle structures for each style
 *      that uses SlipCover. May be empty if there are none, or 'nil' on error.
\******************************************************************************/
 
- ( NSArray * ) findSlipCoverStyles
{
    NSError                * error       = nil;
    NSManagedObjectContext * moc         = [ self managedObjectContext ];
    NSManagedObjectModel   * mom         = [ self managedObjectModel   ];
    NSEntityDescription    * styleEntity = [ mom entitiesByName ][ @"IconStyle" ];
    NSFetchRequest         * request     = [ [ NSFetchRequest alloc ] init ];
    NSPredicate            * predicate   = [ NSPredicate predicateWithFormat: @"usesSlipCover == YES" ];

    [ request setEntity:              styleEntity ];
    [ request setIncludesSubentities: NO          ];
    [ request setPredicate:           predicate   ];

    NSArray * results = [ moc executeFetchRequest: request error: &error ];


    if ( error != nil ) [ NSApp presentError: error ];
    return results; /* Not 'autoreleased' as we don't "own" the object, according to naming conventions; the framework (must have) dealt with it */
}

/******************************************************************************\
 * -checkIconStylesForValidity
 *
 * Icon styles may become invalid if they use SlipCover case designs and one or
 * more of those used designs disappear. Call here to check for such styles and
 * delete them, warning the user about the problem in passing.
 *
 * As a side-effect this method caches the known SlipCover case definitions
 * internally into the public read-only 'slipCoverDefinitions' property.
 *
 * It is safe to call this method even if SlipCover case definitions have not
 * changed, but the method may take a comparatively long time to run, so it
 * should not be called arbitrarily; only call if you *suspect* a change might
 * have occurred (e.g. at application startup, or due to a change event being
 * received for some watched SlipCover case definition filesystem path).
\******************************************************************************/

- ( void ) checkIconStylesForValidity
{
    NSManagedObjectContext * moc = [ self managedObjectContext ];

    /* Find all styles that use SlipCover */

    NSArray * slipCoverStyles = [ self findSlipCoverStyles ];

    /* (Re-)Generate the SlipCover definitions and get an array of unique
     * case names from the results.
     */

    slipCoverDefinitions = [ SlipCoverSupport enumerateSlipCoverDefinitions ];
    NSArray * caseNames  = [ slipCoverDefinitions valueForKeyPath: @"@unionOfObjects.name" ]; /* http://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/KeyValueCoding/Articles/CollectionOperators.html#//apple_ref/doc/uid/20002176-SW2 */

    /* Make sure that all styles use valid names */

    NSMutableArray * impossibleStyles = [ NSMutableArray arrayWithCapacity: 0 ];

    for ( IconStyle * style in slipCoverStyles )
    {
        if ( [ caseNames containsObject: [ style slipCoverName ] ] == NO )
        {
            [ impossibleStyles addObject: style ];
        }
    }

    /* Do we have to delete some styles? */
    
    size_t count = [ impossibleStyles count ];

    if ( count > 0 )
    {
        /* First delete them. If this fails there's not much we can really do
         * except grin and bear it, so errors are ignored. The rest of the
         * application is resilient; the 'Edit Style' panel's menu of styles
         * shows the SlipCover case name stored in the IconStyle object but if
         * any other menu entry is selected, the 'phantom' case design will not
         * be visible when the menu is next shown (that's the way bindings
         * behave when a string doesn't match the bound collection). The
         * command line tool exits indicating 'failed' if it is given a case
         * name which isn't recognised.
         */

        for ( IconStyle * style in impossibleStyles )
        {
            [ moc deleteObject: style ];
        }

        /* Upon saving, the things directly bound to CoreData take care of
         * themselves. MainWindowController updates folder list entries which
         * use deleted styles by an observer it added to the styles collection
         * and ApplicationSpecificPreferencesWindowController takes care of
         * updating the configured default style in the same way, if need be.
         */

        [ moc processPendingChanges ];

        /* Regardless, warn the user about the event */

        NSString * title;
        NSString * message;
        
        if ( count == 1 )
        {
            title = NSLocalizedString(
                @"Icon Style Deleted",
                @"Title of the message shown when one style becomes invalid because SlipCover cases disappear for any reason"
            );
            message = NSLocalizedString(
                @"One of your Add Folder Icons styles used a SlipCover case design which is no longer available. Since the style is now invalid, it has been deleted.",
                @"Message shown when one style becomes invalid because SlipCover cases disappear for any reason"
            );
        }
        else
        {
            title = NSLocalizedString(
                @"Icon Styles Deleted",
                @"Title of the message shown when several styles become invalid because SlipCover cases disappear for any reason"
            );
            message = NSLocalizedString(
                @"%u of your Add Folder Icons styles used SlipCover case designs which are no longer available. Since the styles are now invalid, they have been deleted.",
                @"Message shown when several styles become invalid because SlipCover cases disappear for any reason"
            );
        }

        NSRunInformationalAlertPanel(
            title,
            message,
            NSLocalizedString(
                @"Continue",
                @"Button in the alert shown when one or more styles become invalid because SlipCover cases disappear for any reason"
            ),
            NULL,
            NULL,
            count
        );
    }

    /* Never mind deleting things - should we ask to add some styles if
     * there are case names that *aren't* used by styles?
     */

    NSUserDefaults * defaults       = [ NSUserDefaults standardUserDefaults ];
    NSString       * suppressionKey = @"neverAskAboutSlipCoverAutoAdd";

    if ( [ defaults boolForKey: suppressionKey ] != YES )
    {
        /* 'Re-find' SlipCover styles as code above may have deleted some */

        slipCoverStyles = [ self findSlipCoverStyles ];

        /* For every style in the results, delete used names from a copy of
         * caseNames so that we're left with names which have no corresponding
         * icon style definition.
         */
        
        NSMutableArray * unusedCaseNames = [ NSMutableArray arrayWithArray: caseNames ];

        for ( IconStyle * style in slipCoverStyles )
        {
            NSUInteger index = [ unusedCaseNames indexOfObject: [ style slipCoverName ] ];

            if ( index != NSNotFound /* Should never happen, but... */ )
            {
                [ unusedCaseNames removeObjectAtIndex: index ];
            }
        }

        /* Are there any unused names? */
        
        if ( [ unusedCaseNames count ] > 0 )
        {
            /* Create the alert box */

            NSAlert * alert =
            [
                NSAlert alertWithMessageText: NSLocalizedString( @"Create SlipCover Styles?", @"Title shown in alert asking if SlipCover cases should be automatically added as styles" )
                               defaultButton: NSLocalizedString( @"Create Styles", @"'Yes, add them' button in alert asking if SlipCover cases should be automatically added as styles" )
                             alternateButton: NSLocalizedString( @"Cancel", @"'Cancel' button shown in alert asking if SlipCover cases should be automatically added as styles" )
                                 otherButton: nil
                   informativeTextWithFormat: NSLocalizedString( @"One or more SlipCover case designs not yet used by Add Folder Icons have been found. Would you like to create Add Folder Icons styles for each of those case designs?", @"Question shown in alert asking if SlipCover cases should be automatically added as styles" )
            ];

            [ alert setShowsSuppressionButton: YES ];
            [ alert setShowsHelp:              YES ];
            [ alert setHelpAnchor:             @"slipcover" ];

            /* Run the alert box and only add styles if asked to do so */

            if ( [ alert runModal ] == NSAlertDefaultReturn )
            {
                NSManagedObjectModel * mom         = [ self managedObjectModel   ];
                NSEntityDescription  * styleEntity = [ mom entitiesByName ][ @"IconStyle" ];
                IconStyle            * newStyle;

                /* Convenience... */

                NSNumber * numYes = @YES;
                NSNumber * numNo  = @NO;

                /* Loop over unused case names and created styles for each */

                for ( NSString * unusedCaseName in unusedCaseNames )
                {
                    NSString * styleName =
                    [
                        NSString stringWithFormat: NSLocalizedString( @"SlipCover: %@", @"Name of an auto-defined style created for a SlipCover case"),
                                                   unusedCaseName
                    ];
                
                    newStyle = [ [ IconStyle alloc ] initWithEntity: styleEntity
                                       insertIntoManagedObjectContext: moc ];

                    [ newStyle setIsPreset:      numNo           ];
                    [ newStyle setUsesSlipCover: numYes          ];
                    [ newStyle setSlipCoverName: unusedCaseName  ];
                    [ newStyle setCreatedAt:     [ NSDate date ] ];
                    [ newStyle setName:          styleName       ];
                }

                /* Save the results */

                NSError * error = nil;
                if ( ! [ moc save: &error ] ) [ NSApp presentError: error ];
            }

            /* Whatever happens, make sure that "do not show again" is honoured */

            if ( [ [ alert suppressionButton ] state ] == NSOnState )
            {
                [ defaults setBool: YES forKey: suppressionKey ];
            }
        }
    }
}

/******************************************************************************\
 * -findDefaultIconStyle
 *
 * Return the configured defaulticon style. If there are problems retrieving
 * this, or if it can be retrieved but it is marked as deleted, then the
 * standard preset 'Classic' style will be returned instead. In short, the
 * method guarantees a valid returned style, unless the presets are broken
 * (in that case all bets are off throughout the whole application anyway!).
 *
 * Out: ( IconStyle * ) 
 *      Pointer to the icon style, a managed autoreleased object. Never "nil".
\******************************************************************************/

- ( IconStyle * ) findDefaultIconStyle
{
    NSUserDefaults * userDefaults = [ NSUserDefaults standardUserDefaults ];
    NSString       * objIDString  = [ userDefaults stringForKey: PREFERENCES_DEFAULT_STYLE_KEY ];
    IconStyle      * allElseFails = [ self findClassicIconStyle ];

    /* Turn the object ID string into a "real" object ID */

    CoreDataObjectIDTransformer * vt = ( CoreDataObjectIDTransformer * )
    [
        NSValueTransformer valueTransformerForName: CORE_DATA_OBJECT_ID_TRANSFORMER_NAME
    ];

    NSManagedObjectID * objID = [ vt transformedValue: objIDString ];

    /* Note - possible early exit; use the default 'Classic' preset if all
     * else fails.
     */

    if ( objID == nil ) return allElseFails;

    /* Adapted from and with thanks to:
     * http://cocoawithlove.com/2008/08/safely-fetching-nsmanagedobject-by-uri.html
     */

    IconStyle * obj = ( IconStyle * ) [ [ self managedObjectContext ] objectWithID: objID ];

    /* Have to work harder if this item is a fault; need to fetch it */ 

    if ( [ obj isFault ] == YES )
    {
        /* If we reach here, the related object may or may not be in memory and
         * might not even exist in the persistent store. Try to fetch it now.
         */

        NSFetchRequest * request   = [ [ NSFetchRequest alloc ] init ];
        NSPredicate    * predicate =
        [
            NSPredicate predicateWithFormat: @"SELF = %@",
                                             obj
        ];

        [ request setEntity:    [ objID entity ] ];
        [ request setPredicate: predicate        ];

        /* Return either the first found result or the default 'Classic' preset
         * if nothing is found or there was an error (when 'results' will be nil,
         * so '[results count]' will evaluate to zero).
         */

        NSArray * results = [ [ self managedObjectContext ] executeFetchRequest: request
                                                                          error: nil ];

        if ( [ results count ] > 0 ) obj = results[ 0 ];
        else                         obj = allElseFails;
    }

    /* One final check - code handling changes to the icon style database
     * calls here to obtain a valid configured default style for various
     * reasons. It's possible that the configured style is the one which
     * is being deleted, so always check this and return the 'Classic'
     * preset if need be.
     */

    if ( [ obj isDeleted ] == NO ) return obj;
    else                           return allElseFails;
}

/******************************************************************************\
 * -findClassicIconStyle
 *
 * Return the preset 'Classic' icon style.
 *
 * Out: ( IconStyle * ) 
 *      Pointer to the icon style, a managed autoreleased object. Never "nil".
\******************************************************************************/

- ( IconStyle * ) findClassicIconStyle
{
    IconStyle              * foundStyle;
    NSError                * error       = nil;
    NSManagedObjectContext * moc         = [ self managedObjectContext ];
    NSManagedObjectModel   * mom         = [ self managedObjectModel   ];
    NSEntityDescription    * styleEntity = [ mom entitiesByName ][ @"IconStyle" ];
    NSFetchRequest         * request     = [ [ NSFetchRequest alloc ] init ];
    NSPredicate            * predicate   =
    [
        NSPredicate predicateWithFormat: @"(isPreset == YES) AND (name == %@)",
                                         DEFAULT_ICON_STYLE_NAME
    ];

    [ request setEntity:              styleEntity ];
    [ request setIncludesSubentities: NO          ];
    [ request setPredicate:           predicate   ];

    NSArray * results = [ moc executeFetchRequest: request error: &error ];


    if ( error != nil )
    {
        [ NSApp presentError: error ];
        [ NSApp terminate:    nil   ];
    }

    assert( [ results count ] == 1 );

    foundStyle = results[ 0 ];
    assert( foundStyle != nil );

    return foundStyle;
}

/******************************************************************************\
 * -insertBlankUserStyleAndProcessChanges
 *
 * Create a user (non-preset) icon style with a date-based "undefined..." name
 * and insert it into the managed object context, telling the context to
 * process changes afterwards, but not saving it. The object will be temporary
 * until "-save" is called on the managed object context. If the caller may
 * want to undo this insertion, then the caller is responsible for creating
 * and managing an undo group.
 *
 * Out: ( IconStyle * ) 
 *      Pointer to the icon style, a managed autoreleased object. Might be nil
 *      if things go wrong (e.g. out of memory).
\******************************************************************************/

- ( IconStyle * ) insertBlankUserStyleAndProcessChanges
{
    NSManagedObjectContext * moc         = [ self managedObjectContext ];
    NSManagedObjectModel   * mom         = [ self managedObjectModel   ];
    NSEntityDescription    * styleEntity = [ mom entitiesByName ][ @"IconStyle" ];
    IconStyle              * newStyle    =
    [
        [ IconStyle alloc ] initWithEntity: styleEntity
            insertIntoManagedObjectContext: moc
    ];

    NSString * name =
    [
        NSString stringWithFormat: NSLocalizedString( @"Untitled %@", "Format string used for untitled, new icon styles; the '%@' field must be included and will be filled in with the current date" ),
                                   [ NSDate date ]
    ];

    [ newStyle setCreatedAt: [ NSDate date ] ];
    [ newStyle setName:      name            ];

    /* To avoid having a 'No Value' default selection in the SlipCover list of
     * case names, we need to try and find at least one case definition. If
     * SlipCover isn't present, 'No Value' is fine.
     */

    NSArray * caseDefinitions = [ SlipCoverSupport enumerateSlipCoverDefinitions ];

    if ( [ caseDefinitions count ] > 0 )
    {
        [ newStyle setSlipCoverName: [ caseDefinitions[ 0 ] name ] ];
    }

    /* OK, tell CoreData to process the new object and return the result */

    [ moc processPendingChanges ];

    return newStyle;
}

/******************************************************************************\
 * -pathWatcher:eventOccurred:
 *
 * SCEventListenerProtocol: A watched folder has changed.
 *
 * In: ( SCEvents * ) pathWatcher
 *     The object that has been watching the changed folder.
 *
 *     ( SCEvent * ) event
 *     Pointer to an event describing the change (see "SCEvent.h").
\******************************************************************************/

- ( void ) pathWatcher: ( SCEvents * ) pathWatcher eventOccurred: ( SCEvent * ) event
{
    ( void ) pathWatcher;
    ( void ) event;
    
    [ self checkIconStylesForValidity ];
}

/******************************************************************************\
 * -checkIconStylesForValidity
 *
 * NSAlertDelegate: Show help for the alert. Without this, an alert's help
 * button uses its anchor and a nil book. We want to be more specific. Read
 * the help anchor and specify our particular help book.
 *
 * In:  ( NSAlert * ) alert
 *      Alert in question.
 *
 * Out: If the alert seems to have no help anchor set, NO; else YES.
\******************************************************************************/

- ( BOOL ) alertShowHelp: ( NSAlert * ) alert
{
    NSString * anchor = [ alert helpAnchor ];

    if ( anchor == nil )
    {
        return NO;
    }
    else
    {
        NSString * book = [ [ NSBundle mainBundle ] objectForInfoDictionaryKey: @"CFBundleHelpBookName" ];
        [ [ NSHelpManager sharedHelpManager ] openHelpAnchor: anchor inBook: book ];    
        return YES;
    }
}

@end
