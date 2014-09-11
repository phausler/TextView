//
//  EditorStorage.m
//  TextView
//
//  Created by Philippe Hausler on 9/10/14.
//  Copyright (c) 2014 Philippe Hausler. All rights reserved.
//

#import "EditorStorage.h"

@implementation EditorStorage {
    NSTextStorage *_storage;
    NSMutableIndexSet *_lines;
    NSMutableDictionary *_lineIndicies;
}

- (instancetype)initWithString:(NSString *)str
{
    return [self initWithString:str attributes:nil];
}

- (instancetype)initWithString:(NSString *)str attributes:(NSDictionary *)attrs
{
    return [self initWithAttributedString:[[NSAttributedString alloc] initWithString:str attributes:attrs]];
}

- (instancetype)initWithAttributedString:(NSAttributedString *)attrStr
{
    self = [super init];
    
    if (self)
    {
        _lines = [[NSMutableIndexSet alloc] init];
        _storage = [[NSTextStorage alloc] initWithAttributedString:attrStr];
        _lineIndicies = [[NSMutableDictionary alloc] init];
        [[_storage string] enumerateSubstringsInRange:NSMakeRange(0, [_storage length]) options:NSStringEnumerationByLines usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
            [_lines addIndex:enclosingRange.location];
        }];
    }
    
    return self;
}

- (NSString *)string
{
    return [_storage string];
}

- (NSDictionary *)attributesAtIndex:(NSUInteger)location effectiveRange:(NSRangePointer)range
{
    return [_storage attributesAtIndex:location effectiveRange:range];
}

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)str
{
    NSUInteger loc = [_lines indexGreaterThanIndex:range.location];

    NSUInteger lesserIndex = [_lines indexLessThanIndex:range.location];
    NSUInteger greaterIndex = [_lines indexGreaterThanIndex:NSMaxRange(range)];
    
    if (lesserIndex == NSNotFound)
    {
        lesserIndex = range.location;
    }
    
    if (greaterIndex == NSNotFound)
    {
        greaterIndex = NSMaxRange(range);
    }
    
    NSRange removeRange = NSMakeRange(lesserIndex, greaterIndex - lesserIndex);
    NSUInteger count = removeRange.length;
    NSUInteger *indicies = alloca(sizeof(NSUInteger) * count);
    count = [_lines getIndexes:indicies maxCount:count inIndexRange:NULL];
    
    for (NSUInteger idx = 0; idx < count; idx++)
    {
        [_lineIndicies removeObjectForKey:@(indicies[idx])];
    }
    
    [_lines removeIndexesInRange:removeRange];
    
    if (loc != NSNotFound)
    {
        [_lines shiftIndexesStartingAtIndex:loc by:[str length] - range.length];
    }
    
    [_storage replaceCharactersInRange:range withString:str];

    if (NSMaxRange(removeRange) >= [_storage length])
    {
        return;
    }
    
    [[_storage string] enumerateSubstringsInRange:removeRange options:NSStringEnumerationByLines usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
        [_lines addIndex:enclosingRange.location];
    }];
}

- (void)setAttributes:(NSDictionary *)attrs range:(NSRange)range
{
    [_storage setAttributes:attrs range:range];
}

- (void)addLayoutManager:(NSLayoutManager *)obj
{
    [_storage addLayoutManager:obj];
}

- (void)removeLayoutManager:(NSLayoutManager *)obj
{
    [_storage removeLayoutManager:obj];
}

- (NSArray *)layoutManagers
{
    return _storage.layoutManagers;
}

- (void)edited:(NSUInteger)editedMask range:(NSRange)range changeInLength:(NSInteger)delta
{
    [_storage edited:editedMask range:range changeInLength:delta];
}

- (void)processEditing
{
    [_storage processEditing];
}

- (void)invalidateAttributesInRange:(NSRange)range
{
    [_storage invalidateAttributesInRange:range];
}

- (void)ensureAttributesAreFixedInRange:(NSRange)range
{
    [_storage ensureAttributesAreFixedInRange:range];
}

- (BOOL)fixesAttributesLazily
{
    return _storage.fixesAttributesLazily;
}

- (NSUInteger)editedMask
{
    return _storage.editedMask;
}

- (NSRange)editedRange
{
    return _storage.editedRange;
}

- (NSInteger)changeInLength
{
    return _storage.changeInLength;
}

- (id<NSTextStorageDelegate>)delegate
{
    return _storage.delegate;
}

- (void)setDelegate:(id<NSTextStorageDelegate>)delegate
{
    _storage.delegate = delegate;
}

- (NSUInteger)lineIndex:(NSUInteger)start
{
    if (start == NSNotFound)
    {
        _lineIndicies[@(0)] = @(0);
        return 0;
    }
    
    start = [_lines indexGreaterThanOrEqualToIndex:start];
    NSNumber *index = _lineIndicies[@(start)];

    if (index != nil)
    {
        return [index unsignedIntegerValue];
    }
    
    NSUInteger idx = [self lineIndex:[_lines indexLessThanIndex:start]] + 1;
    _lineIndicies[@(start)] = @(idx);
    return idx;
}

@end
