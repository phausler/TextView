//
//  EditorView.m
//  TextView
//
//  Created by Philippe Hausler on 9/8/14.
//  Copyright (c) 2014 Philippe Hausler. All rights reserved.
//

#import <QuartzCore/CATextLayer.h>

#import "EditorView.h"
#import "EditorStorage.h"

NSString *const EditorViewTabIndent = @"\t";

@interface EditorView ()
@property (nonatomic, readonly) NSLayoutManager *layoutManager;
@property (nonatomic, readonly) NSTextContainer *textContainer;
@property (nonatomic, readonly) EditorStorage *storage;
@end

@implementation EditorView {
    NSPointerArray *_selectedRanges;
    NSRange _markedRange;
    NSLayoutManager *_layoutManager;
    NSTextContainer *_textContainer;
    EditorStorage *_storage;
    NSTimer *_caretBlink;
    NSScroller *_scroller;
    BOOL _caretVisible;
    BOOL _isDrawing;
    NSSize _contentSize;
}

static NSUInteger rangeHash(const NSRange *item, NSUInteger (*size)(const NSRange *item))
{
    NSCAssert(item != NULL, @"range pointer cannot be NULL");
    NSCAssert(size(item) == sizeof(NSRange), @"range pointer is unexpected size");
    return item->location ^ item->length;
}

static BOOL rangeEqual(const NSRange *item1, const NSRange *item2, NSUInteger (*size)(const NSRange *item))
{
    NSCAssert(item1 != NULL, @"range pointer cannot be NULL");
    NSCAssert(size(item1) == sizeof(NSRange), @"range pointer is unexpected size");
    NSCAssert(item2 != NULL, @"range pointer cannot be NULL");
    NSCAssert(size(item2) == sizeof(NSRange), @"range pointer is unexpected size");
    if (item1 == item2)
    {
        return YES;
    }
    
    return item1->location == item2->location &&
           item2->length == item2->length;
}

static NSUInteger rangeSize(const NSRange *item)
{
    NSCAssert(item != NULL, @"range pointer cannot be NULL");
    return sizeof(NSRange);
}

static NSString *rangeDescription(const NSRange *item)
{
    NSCAssert(item != NULL, @"range pointer cannot be NULL");
    return NSStringFromRange(*item);
}

static void rangeRelinquish(NSRange *item, NSUInteger (*size)(const void *item))
{
    free(item);
}

void *rangeAcquire(const NSRange *src, NSUInteger (*size)(const void *item), BOOL shouldCopy)
{
    NSRange *ptr = (NSRange *)malloc(size(src));
    ptr->location = src->location;
    ptr->length = src->length;
    return ptr;
}

- (void)setup
{
    NSPointerFunctions *rangeFunctions = [[NSPointerFunctions alloc] init];
    rangeFunctions.hashFunction = (NSUInteger (*)(const void *, NSUInteger (*)(const void *)))&rangeHash;
    rangeFunctions.isEqualFunction = (BOOL (*)(const void *, const void*, NSUInteger (*)(const void *)))&rangeEqual;
    rangeFunctions.sizeFunction = (NSUInteger (*)(const void *))&rangeSize;
    rangeFunctions.descriptionFunction = (NSString *(*)(const void *item))&rangeDescription;
    
    rangeFunctions.relinquishFunction = (void (*)(const void *, NSUInteger (*)(const void *)))&rangeRelinquish;
    rangeFunctions.acquireFunction = (void *(*)(const void *, NSUInteger (*)(const void *), BOOL))&rangeAcquire;
    
    _selectedRanges = [[NSPointerArray alloc] initWithPointerFunctions:rangeFunctions];
    

    
    _markedRange = NSMakeRange(NSNotFound, 0);
    
    self.indentString = [EditorView spaceIndentString:4];
    self.lineEnding = EditorViewUnixEnding;
    
    NSDictionary *attrs = @{NSForegroundColorAttributeName: [NSColor whiteColor], NSFontAttributeName: [NSFont fontWithName:@"Menlo" size:10.0]};
    _storage = [[EditorStorage alloc] initWithString:@"" attributes:attrs];

    NSRange selection = NSMakeRange(0, 0);
    [_selectedRanges addPointer:&selection];
    _storage.delegate = self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    
    if (self)
    {
        [self setup];
    }
    
    return self;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    
    if (self)
    {
        [self setup];
    }
    
    return self;
}

+ (NSString *)spaceIndentString:(NSUInteger)numSpaces
{
    static NSMutableDictionary *indents = nil;
    static dispatch_once_t once = 0L;
    dispatch_once(&once, ^{
        indents = [@{@(1): @" ", @(2): @"  ", @(3): @"   ", @(4): @"    ", @(8): @"        "} mutableCopy];
    });
    NSString *indent = indents[@(numSpaces)];
    if (indent == nil)
    {
        indent = [NSString stringWithFormat:@"%*.0i", (int)numSpaces, 0];
        indents[@(numSpaces)] = indent;
    }
    
    return indent;
}

- (id)text
{
    return [self.storage string];
}

- (void)setText:(id)string
{
    [self.storage beginEditing];
    
    if ([string isKindOfClass:[NSAttributedString class]])
    {
        [self.storage setAttributedString:string];
    }
    else
    {
        [self.storage replaceCharactersInRange:NSMakeRange(0, [_storage length]) withString:string];
    }
    
    [self.storage endEditing];
}

- (void)textStorageDidProcessEditing:(NSNotification *)notification
{
    [self unmarkText];
    [[self inputContext] invalidateCharacterCoordinates];
    
    if (_isDrawing)
    {
        return;
    }
    
    [self setNeedsDisplay:YES];
}

- (NSLayoutManager *)layoutManager
{
    if (_layoutManager == nil)
    {
        _layoutManager = [[NSLayoutManager alloc] init];
        [self.storage addLayoutManager:_layoutManager];
    }
    
    return _layoutManager;
}

- (NSTextContainer *)textContainer
{
    if (_textContainer == nil)
    {
        _textContainer = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(NSWidth(self.frame), CGFLOAT_MAX)];
        [self.layoutManager addTextContainer:_textContainer];
    }
    
    return _textContainer;
}

- (NSRect)caretRectForSelectionAtIndex:(NSUInteger)index
{
    NSRange *range = [_selectedRanges pointerAtIndex:index];
    NSRect caretRect = [self firstRectForCharacterRange:*range actualRange:NULL];
    caretRect.size.width = 1.0;
    
    return caretRect;
}

- (void)blinkCaret
{
    _caretVisible = !_caretVisible;
    for (NSUInteger idx = 0; idx < [_selectedRanges count]; idx++)
    {
        [self setNeedsDisplayInRect:[self caretRectForSelectionAtIndex:idx]];
    }
}

- (void)startCaretAnimation
{
    if (_caretBlink == nil)
    {
        _caretBlink = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(blinkCaret) userInfo:nil repeats:YES];
    }
}

- (void)stopCaretAnimation
{
    [_caretBlink invalidate];
    _caretBlink = nil;
    for (NSUInteger idx = 0; idx < [_selectedRanges count]; idx++)
    {
        [self setNeedsDisplayInRect:[self caretRectForSelectionAtIndex:idx]];
    }
}

- (void)compactRanges
{
    NSUInteger count = [_selectedRanges count];
    NSRange *ranges = alloca(sizeof(NSRange) * count);
    for (NSUInteger idx = 0; idx < count; idx++)
    {
        ranges[idx] = *(NSRange *)[_selectedRanges pointerAtIndex:idx];
    }
    
    for (NSUInteger idx = 0; idx < count; idx++)
    {
        for (NSUInteger next = idx + 1; next < count; next++)
        {
            if (ranges[idx].location == ranges[next].location &&
                ranges[idx].length == ranges[next].length)
            {
                ranges[next].location = NSNotFound;
            }
        }
    }
    
    for (; count > 0; count--)
    {
        if (ranges[count - 1].location == NSNotFound)
        {
            [_selectedRanges removePointerAtIndex:count - 1];
        }
    }
    
    [_selectedRanges compact];
}

- (BOOL)isFlipped
{
    return YES;
}

- (void)scrollWheel:(NSEvent *)theEvent
{
    [super scrollWheel:theEvent];
    [self setNeedsDisplay:YES];
}

- (NSSize)contentSize:(NSRect)container
{
    NSRange r = [self.layoutManager glyphRangeForTextContainer:self.textContainer];
    if (r.length == 0)
    {
        return container.size;
    }
    else
    {
        return NSMakeSize(NSWidth(container), MAX(NSHeight(container), [self.layoutManager usedRectForTextContainer:self.textContainer].size.height));
    }
}

- (void)applyContentSize
{
    NSRect frame = self.frame;
    NSScrollView *scrolView = self.enclosingScrollView;
    
    if (scrolView)
    {
        NSSize sz = [self contentSize:[scrolView documentVisibleRect]];
        if (NSEqualSizes(sz, frame.size))
        {
            return;
        }
        frame.size = sz;
    }
    
    [super setFrame:frame];
}

- (void)setFrame:(NSRect)frame
{
    NSScrollView *scrolView = self.enclosingScrollView;
    
    if (scrolView)
    {
        frame.size = [self contentSize:[scrolView documentVisibleRect]];
    }
    
    [super setFrame:frame];
}

- (void)drawRect:(NSRect)rect
{
    [[NSColor darkGrayColor] setFill];
    NSRectFill(rect);
    
    NSScrollView *scrolView = self.enclosingScrollView;
    if (scrolView)
    {
        NSRect intersection = NSIntersectionRect(rect, [scrolView documentVisibleRect]);
        
        if (NSIsEmptyRect(intersection))
        {
            return;
        }
        
        rect = intersection;
    }
    
    _isDrawing = YES;
    NSRange glyphRange = [self.layoutManager glyphRangeForBoundingRect:rect inTextContainer:self.textContainer];
    NSPoint start = NSMakePoint(30, 0);
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSRightTextAlignment;
    NSDictionary *attrs = @{ NSParagraphStyleAttributeName: style, NSForegroundColorAttributeName: [NSColor lightGrayColor], NSFontAttributeName: [NSFont fontWithName:@"Menlo" size:9.0]};
    NSUInteger currentIndex = [self.storage.lines indexGreaterThanOrEqualToIndex:glyphRange.location];
    
    while (currentIndex != NSNotFound && currentIndex <= NSMaxRange(glyphRange)) {
        NSRect lineRect = [self.layoutManager lineFragmentUsedRectForGlyphAtIndex:currentIndex effectiveRange:NULL];
        lineRect.size.width = start.x;
        if (NSIntersectsRect(lineRect, rect))
        {
            [[NSColor darkGrayColor] setFill];
            NSRectFill(lineRect);

            NSUInteger lineNo = [self.storage lineIndex:currentIndex];
            [[NSString stringWithFormat:@"%lu", lineNo] drawInRect:lineRect withAttributes:attrs];
        }
        currentIndex = [self.storage.lines indexGreaterThanIndex:currentIndex];
    }

    [self.layoutManager drawBackgroundForGlyphRange:glyphRange atPoint:start];
    [self.layoutManager drawGlyphsForGlyphRange:glyphRange atPoint:start];
    
    if (_caretVisible)
    {
        for (NSUInteger idx = 0; idx < [_selectedRanges count]; idx++)
        {
            NSRect caretRect = [self caretRectForSelectionAtIndex:idx];
            caretRect = NSOffsetRect(caretRect, start.x, start.y);
            if (NSIntersectsRect(caretRect, rect))
            {
                [[NSColor whiteColor] setFill];
                NSRectFill(caretRect);
            }
        }
    }
    
    _isDrawing = NO;
}

- (BOOL)acceptsFirstResponder
{
    return YES;
}

- (BOOL)becomeFirstResponder
{
    [self startCaretAnimation];
    return YES;
}

- (BOOL)resignFirstResponder
{
    _caretVisible = NO;
    [self stopCaretAnimation];
    
    return YES;
}

- (void)keyDown:(NSEvent *)theEvent
{
    _caretVisible = YES;
    [self stopCaretAnimation];
    [NSCursor setHiddenUntilMouseMoves:YES];
    [[self inputContext] handleEvent:theEvent];
}

- (void)mouseDown:(NSEvent *)theEvent
{
    [[self inputContext] handleEvent:theEvent];
}

- (void)mouseDragged:(NSEvent *)theEvent
{
    [[self inputContext] handleEvent:theEvent];
}

- (void)mouseUp:(NSEvent *)theEvent
{
    [[self inputContext] handleEvent:theEvent];
}

- (void)keyUp:(NSEvent *)theEvent
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(startCaretAnimation) object:nil];
    [self performSelector:@selector(startCaretAnimation) withObject:nil afterDelay:0.5];
}

- (void)insertNewline:(id)sender
{
    switch (self.lineEnding)
    {
        case EditorViewUnixEnding:
            [self insertText:@"\n"];
            break;
        case EditorViewMacClassicEnding:
            [self insertText:@"\r"];
            break;
        case EditorViewWindowsEnding:
            [self insertText:@"\r\n"];
            break;
    }
}

- (void)insertTab:(id)sender
{
    [self insertText:self.indentString];
}

- (void)moveRight:(id)sender
{
    [self moveForward:sender];
}

- (void)moveForward:(id)sender
{
    for (NSUInteger idx = 0; idx < [_selectedRanges count]; idx++)
    {
        [self setNeedsDisplayInRect:[self caretRectForSelectionAtIndex:idx]];
    }
    
    NSUInteger length = [self.storage length];
    
    for (NSUInteger idx = 0; idx < [_selectedRanges count]; idx++)
    {
        NSRange *range = (NSRange *)[_selectedRanges pointerAtIndex:idx];
        if (range->location < length)
        {
            range->location++;
        }
    }
    
    [self compactRanges];
    
    for (NSUInteger idx = 0; idx < [_selectedRanges count]; idx++)
    {
        [self setNeedsDisplayInRect:[self caretRectForSelectionAtIndex:idx]];
    }
}


- (void)moveLeft:(id)sender
{
    [self moveBackward:sender];
}

- (void)moveBackward:(id)sender
{
    for (NSUInteger idx = 0; idx < [_selectedRanges count]; idx++)
    {
        [self setNeedsDisplayInRect:[self caretRectForSelectionAtIndex:idx]];
    }
    
    for (NSUInteger idx = 0; idx < [_selectedRanges count]; idx++)
    {
        NSRange *range = (NSRange *)[_selectedRanges pointerAtIndex:idx];
        if (range->location > 0)
        {
            range->location--;
        }
    }
    
    [self compactRanges];
    
    for (NSUInteger idx = 0; idx < [_selectedRanges count]; idx++)
    {
        [self setNeedsDisplayInRect:[self caretRectForSelectionAtIndex:idx]];
    }
}

- (void)selectAll:(id)sender
{
    for (NSUInteger count = [_selectedRanges count]; count > 0; count--)
    {
        [_selectedRanges removePointerAtIndex:count - 1];
    }
    
    NSRange range = NSMakeRange(0, [self.storage length]);
    [_selectedRanges addPointer:&range];
}

- (void)deleteBackward:(id)sender
{
    for (NSUInteger count = [_selectedRanges count]; count > 0; count--)
    {
        NSRange *deleteRange = (NSRange *)[_selectedRanges pointerAtIndex:count - 1];
    
        if (deleteRange->length == 0)
        {
            if (deleteRange->location == 0)
            {
                return;
            }
            else
            {
                deleteRange->location -= 1;
                deleteRange->length = 1;
                NSRange range = [[self.storage string] rangeOfComposedCharacterSequencesForRange:*deleteRange];
                deleteRange->location = range.location;
                deleteRange->length = range.length;
            }
        }

        [self deleteCharactersInRange:*deleteRange];
        
        deleteRange->location = deleteRange->location;
        deleteRange->length = 0;
    }
    
    [self compactRanges];
}

- (void)deleteForward:(id)sender
{
    for (NSUInteger count = [_selectedRanges count]; count > 0; count--)
    {
        NSRange *deleteRange = (NSRange *)[_selectedRanges pointerAtIndex:count - 1];
        
        if (deleteRange->length == 0)
        {
            if (deleteRange->location == [self.storage length])
            {
                return;
            }
            else
            {
                deleteRange->length = 1;
                NSRange range = [[self.storage string] rangeOfComposedCharacterSequencesForRange:*deleteRange];
                deleteRange->location = range.location;
                deleteRange->length = range.length;
            }
        }
        
        [self deleteCharactersInRange:*deleteRange];
        
        deleteRange->location = deleteRange->location;
        deleteRange->length = 0;
    }
    
    [self compactRanges];
}

- (void)insertText:(id)insertString
{
    [self.storage beginEditing];
    
    for (NSUInteger count = [_selectedRanges count]; count > 0; count--)
    {
        NSRange *insertRange = (NSRange *)[_selectedRanges pointerAtIndex:count - 1];

        
        if ([insertString isKindOfClass:[NSAttributedString class]])
        {
            [self.storage replaceCharactersInRange:*insertRange withAttributedString:insertString];
        }
        else
        {
            [self.storage replaceCharactersInRange:*insertRange withString:insertString];
        }
        
        insertRange->location += [insertString length];
    }
    
    [self compactRanges];
    [self.storage endEditing];
}

- (void)deleteCharactersInRange:(NSRange)range
{
    if (NSLocationInRange(NSMaxRange(range), _markedRange))
    {
        _markedRange.length -= NSMaxRange(range) - _markedRange.location;
        _markedRange.location = range.location;
    }
    else if (_markedRange.location > range.location)
    {
        _markedRange.location -= range.length;
    }
    
    if (_markedRange.length == 0)
    {
        [self unmarkText];
    }

    [self.storage deleteCharactersInRange:range];
}

- (void)insertText:(id)aString replacementRange:(NSRange)replacementRange
{
    if (replacementRange.location == NSNotFound)
    {
        if (_markedRange.location != NSNotFound)
        {
            replacementRange = _markedRange;
        }
        else
        {
            [self insertText:aString];
            return;
        }
    }
    
    [self.storage beginEditing];
    
    if ([aString isKindOfClass:[NSAttributedString class]])
    {
        [self.storage replaceCharactersInRange:replacementRange withAttributedString:aString];
    }
    else
    {
        [self.storage replaceCharactersInRange:replacementRange withString:aString];
    }
    
    [self.storage endEditing];
}

- (void)doCommandBySelector:(SEL)aSelector
{
    [super doCommandBySelector:aSelector];
}

- (void)setMarkedText:(id)aString selectedRange:(NSRange)newSelection replacementRange:(NSRange)replacementRange
{
    if (replacementRange.location == NSNotFound)
    {
        if (_markedRange.location != NSNotFound)
        {
            replacementRange = _markedRange;
        }
        else
        {
            return;
        }
    }
    
    [self.storage beginEditing];
    
    if ([aString length] == 0)
    {
        [self.storage deleteCharactersInRange:replacementRange];
        [self unmarkText];
    }
    else
    {
        _markedRange = NSMakeRange(replacementRange.location, [aString length]);
        if ([aString isKindOfClass:[NSAttributedString class]])
        {
            [self.storage replaceCharactersInRange:replacementRange withAttributedString:aString];
        }
        else
        {
            [self.storage replaceCharactersInRange:replacementRange withString:aString];
        }
    }
    
    [self.storage endEditing];
}

- (void)unmarkText
{
    _markedRange = NSMakeRange(NSNotFound, 0);
    [[self inputContext] discardMarkedText];
}

- (NSRange)selectedRange
{
    NSRange r = NSMakeRange(NSNotFound, 0);
    
    for (NSUInteger idx = 0; idx < [_selectedRanges count]; idx++)
    {
        NSRange *range = (NSRange *)[_selectedRanges pointerAtIndex:idx];
        if (r.location != NSNotFound)
        {
            r = NSUnionRange(*range, r);
        }
        else
        {
            r = *range;
        }
    }
    
    return r;
}

- (NSRange)markedRange
{
    return _markedRange;
}

- (BOOL)hasMarkedText
{
    return (_markedRange.location == NSNotFound ? NO : YES);
}

- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)aRange actualRange:(NSRangePointer)actualRange
{
    NSRange found = aRange;
    [self.storage attributesAtIndex:aRange.location longestEffectiveRange:&found inRange:aRange];
    
    if (actualRange != NULL)
    {
        *actualRange = found;
    }
    
    return [self.storage attributedSubstringFromRange:found];
}

- (NSArray *)validAttributesForMarkedText
{
    return @[NSMarkedClauseSegmentAttributeName, NSGlyphInfoAttributeName];
}

- (NSRect)firstRectForCharacterRange:(NSRange)aRange actualRange:(NSRangePointer)actualRange
{
    NSRange glyphRange = [self.layoutManager glyphRangeForCharacterRange:aRange actualCharacterRange:actualRange];
    NSRect glyphRect = [self.layoutManager boundingRectForGlyphRange:glyphRange inTextContainer:self.textContainer];
    
    return glyphRect;
}

- (NSUInteger)characterIndexForPoint:(NSPoint)aPoint
{
    NSRect rect;
    rect.origin = aPoint;
    NSPoint localPoint = [self convertPointFromBacking:[[self window] convertRectFromScreen:rect].origin];
    NSUInteger glyphIndex = [self.layoutManager glyphIndexForPoint:localPoint inTextContainer:self.textContainer fractionOfDistanceThroughGlyph:NULL];
    return [self.layoutManager characterIndexForGlyphAtIndex:glyphIndex];
}

- (NSAttributedString *)attributedString
{
    return self.storage;
}

@end
