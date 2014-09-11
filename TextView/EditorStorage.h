//
//  EditorStorage.h
//  TextView
//
//  Created by Philippe Hausler on 9/10/14.
//  Copyright (c) 2014 Philippe Hausler. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface EditorStorage : NSTextStorage

@property (nonatomic, readonly) NSIndexSet *lines;

- (NSUInteger)lineIndex:(NSUInteger)start;

@end
