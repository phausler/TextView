//
//  EditorView.h
//  TextView
//
//  Created by Philippe Hausler on 9/8/14.
//  Copyright (c) 2014 Philippe Hausler. All rights reserved.
//

#import <AppKit/AppKit.h>

NSString *const EditorViewTabIndent;

typedef enum {
    EditorViewUnixEnding,
    EditorViewMacClassicEnding,
    EditorViewWindowsEnding,
} EditorViewLineEnding;

@interface EditorView : NSView <NSTextInputClient, NSTextStorageDelegate>

@property (nonatomic, copy) id text;
@property (nonatomic, copy) NSString *indentString;
@property (nonatomic, assign) EditorViewLineEnding lineEnding;

+ (NSString *)spaceIndentString:(NSUInteger)numSpaces;

@end
