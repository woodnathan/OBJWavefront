//
//  OBJWavefrontFile.m
//
//  Copyright (c) 2014 Nathan Wood (http://www.woodnathan.com/)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "OBJWavefrontFile.h"

#if OBJWavefrontCacheUsesCommonCrypto
#import <CommonCrypto/CommonCrypto.h>
#import <stdio.h>
#import <fcntl.h>
#endif

#import <sys/mman.h> // Used for mmap in the OBJWavefrontCache

#define IDENTIFIER_LENGTH 2 // eg. v, vn, vt, f
#define OBJ_BUFFER_OFFSET(i) ((char *)NULL + (i))

NSString *const OBJWavefrontErrorDomain = @"OBJWavefrontErrorDomain";

typedef NS_ENUM(NSUInteger, OBJWavefrontLineDefinition) {
    OBJWavefrontUnknownDefinition = 0,
    OBJWavefrontVertexDefinition = 1,
    OBJWavefrontNormalDefinition,
    OBJWavefrontTextureCoordDefinition,
    OBJWavefrontFaceDefinition,
};

/**
 *  The name for the default (unnamed) object in the cache
 */
static NSString *const OBJWavefrontCacheRootObjectName = @"root_object";

#pragma mark - Class Extensions

@interface OBJWavefrontFile () {
  @private
    /**
     *  The path to the Wavefront .obj file
     */
    NSString *_path;
    
    /**
     *  The array of OBJWavefrontObject instances loaded from the file or data
     */
    NSArray *_objects;
}

/**
 *  Parses objects from the contents and data
 *  The contents should be a string representation of the data
 *
 *  @param contents The contents of the .obj file/data
 *  @param data     The data of the .obj file/data
 *
 *  @return An array of OBJWavefrontObject instances
 */
- (NSArray *)parseObjectsWithContents:(NSString *)contents data:(NSData *)data;

@end

@interface OBJWavefrontObject () {
  @protected
    /**
     *  The number of positions (v)
     *  Used to allocate _positionBuffer
     */
    unsigned long _positionCount;
    /**
     *  The number of normals (vn)
     *  Used to allocate _normalBuffer
     */
    unsigned long _normalCount;
    /**
     *  The number of texture coords (vt)
     *  Used to allocate _texCoordBuffer
     */
    unsigned long _texCoordCount;
    /**
     *  The number of faces (f)
     *  Used to allocate _faceIndexBuffer
     */
    unsigned long _faceCount;
    
    /**
     *  This is the number of dimensions in a position coordinate
     *  For example:
     *    "v 0.0 0.0 0.0"     = 3
     *    "v 0.0 0.0 0.0 0.0" = 4
     */
    unsigned int _positionSize:3; // Max Value: d(4) = b(100)
    
    /**
     *  This is the number of dimensions in a texture coordinate
     *  For example:
     *    "vt 0.0 0.0"     = 2
     *    "vt 0.0 0.0 0.0" = 3
     */
    unsigned int _texCoordSize:2; // Max Value: d(3) = b(11)
    
    /**
     *  This is the number of components in a face
     *  For example:
     *    "f 1/1/1 1/1/1 1/1/1"       = 3
     *    "f 1/1/1 1/1/1 1/1/1 1/1/1" = 4
     */
    unsigned int _faceComponentCount:3; // Max Value: d(4) = b(100)
    
    /**
     *  Temporary buffer for all the positions
     */
    float *_positionBuffer;
    /**
     *  Temporary buffer for all the normals
     */
    float *_normalBuffer;
    /**
     *  Temporary buffer for all the texture coords
     */
    float *_texCoordBuffer;
    /**
     *  Temporary buffer for all the face indices
     */
    int *_faceIndexBuffer;
    
    /**
     *  The object's ARRAY_BUFFER
     */
    NSData *_buffer;
}

- (instancetype)initWithObjectData:(NSData *)data;

@property (nonatomic, weak) OBJWavefrontFile *file;

@property (nonatomic, strong) NSData *objectData;
@property (nonatomic, readonly) NSString *contents;

@property (nonatomic, copy, readwrite) NSString *name;
@property (nonatomic, assign, readwrite) NSRange range;

/**
 *  Finalizes the object, parsing all information, allocating temporary and final buffers
 *
 *  - (void)finalize is taken by NSObject for Garbage Collection
 */
- (void)complete;

/**
 *  Parses out count and size information for allocating buffers
 */
- (void)parseInformation;

/**
 *  Counts the number of coordinate components in a string
 *  Example:
 *    "v 0.0 0.0 0.0 0.0" would return 4
 *    "vt 0.0 0.0 0.0" would return 3
 *
 *  @param string        A string containing floating point numbers seperated by whitespace
 *  @param lastComponent The last floating point value that was read
 *
 *  @return The number of floating point components in the string
 */
- (unsigned int)numberOfCoordinateComponentsInString:(NSString *)string lastComponent:(float *)lastComponent;

/**
 *  This calculates the number of components in a face string
 *
 *  @param string A face string like "f 1/1/1 1/1/1 1/1/1"
 *
 *  @return The number of triplets of indexes
 */
- (unsigned int)numberOfComponentsInFaceString:(NSString *)string;

/**
 *  Allocates temporary buffers
 *  One for position, normal, texture, and face indices
 */
- (void)allocateTemporaryBuffers;

/**
 *  Deallocates the temporary buffers
 */
- (void)deallocateTemporaryBuffers;

/**
 *  Parses the data into the temporary buffers
 */
- (void)parseData;
/**
 *  Packs the seperate buffers into a buffer with a similar format to:
 *    v.x,v.y,v.z,vn.x,vn.y,vn.z,vt.u,vt.v
 */
- (void)buildPackedBuffer;

/**
 *  Enumerates lines in the Wavefront .obj data and identifies them
 *
 *  @param block The block to apply to each line
 */
- (void)enumerateLinesUsingBlock:(void (^)(NSString *line, OBJWavefrontLineDefinition definition))block;

@end

@interface OBJWavefrontCache ()

+ (NSString *)cacheKeyWithFileAtPath:(NSString *)path options:(OBJWavefrontCacheOptions)options;
+ (NSString *)cacheKeyForString:(NSString *)string;

/**
 *  The file path points to the originating wavefront path
 */
- (instancetype)initWithFileAtPath:(NSString *)path options:(OBJWavefrontCacheOptions)options error:(NSError **)error;

@property (nonatomic, readonly) NSString *cachePath;

@end

@interface OBJWavefrontObject (Caching)

- (BOOL)writeToFile:(NSString *)path;

- (NSData *)archiveMetadata;
- (void)unarchiveMetadata:(NSData *)data;

@end

@interface OBJWavefrontCachedObject : OBJWavefrontObject

@end

@interface OBJMappedData () {
  @private
    void *_mappedBytes; // mmap pointer
    void *_bytes;       // start address, may be same as _mappedBytes
    NSUInteger _length;
}

@property (nonatomic, readonly) NSFileHandle *fileHandle;

@end

#pragma mark - OBJWavefrontFile Implementation

@implementation OBJWavefrontFile

@synthesize cache = _cache;

- (instancetype)init
{
    return [self initWithContentsOfFile:nil];
}

- (instancetype)initWithContentsOfFile:(NSString *)path
{
    return [self initWithContentsOfFile:path error:nil];
}

- (instancetype)initWithContentsOfFile:(NSString *)path error:(NSError *__autoreleasing *)error
{
    OBJWavefrontCacheOptions options = OBJWavefrontCacheLoadMappedData | OBJWavefrontCacheHashUsingFileContents;
    return [self initWithContentsOfFile:path options:options error:error];
}

- (instancetype)initWithContentsOfFile:(NSString *)path options:(OBJWavefrontCacheOptions)options error:(NSError *__autoreleasing *)error
{
    NSParameterAssert(path != nil);
    
    OBJWavefrontCache *cache = [[OBJWavefrontCache alloc] initWithFileAtPath:path options:options error:error];
    return [self initWithContentsOfFile:path cache:cache];
}

- (instancetype)initWithContentsOfFile:(NSString *)path cache:(OBJWavefrontCache *)cache
{
    self = [super init];
    if (self)
    {
        self->_path = path;
        
        self->_cache = cache;
    }
    return self;
}

- (instancetype)initWithData:(NSData *)data cache:(OBJWavefrontCache *)cache
{
    NSParameterAssert(data != nil);
    
    self = [self initWithContentsOfFile:nil cache:cache];
    if (self)
    {
        self->_cache = cache;
        
        
        NSString *contents = [[NSString alloc] initWithBytesNoCopy:(void *)data.bytes
                                                            length:data.length
                                                          encoding:NSASCIIStringEncoding
                                                      freeWhenDone:NO];
        
        self->_objects = [self parseObjectsWithContents:contents data:data];
        contents = nil, data = nil;
    }
    return self;
}

#pragma mark Accessors

- (NSArray *)objectsWithError:(NSError *__autoreleasing *)error
{
    if (self->_objects == nil)
    {
        NSString *const path = self->_path;
        NSAssert(path != nil, @"File path is required");
        
        const NSDataReadingOptions opts = NSDataReadingMappedIfSafe;
        NSData *mappedData = [[NSData alloc] initWithContentsOfFile:path
                                                            options:opts
                                                              error:error];
        
        NSString *contents = [[NSString alloc] initWithBytesNoCopy:(void *)mappedData.bytes
                                                            length:mappedData.length
                                                          encoding:NSASCIIStringEncoding
                                                      freeWhenDone:NO];
        
        self->_objects = [self parseObjectsWithContents:contents data:mappedData];
        contents = nil, mappedData = nil;
    }
    return self->_objects;
}

- (NSArray *)objects
{
    if (self->_objects == nil)
        self->_objects = [self objectsWithError:nil];
    return self->_objects;
}

#pragma mark File Object Parser

- (NSArray *)parseObjectsWithContents:(NSString *)contents data:(NSData *)data
{
    OBJWavefrontCache *cache = self.cache;
    NSMutableArray *objects = [[NSMutableArray alloc] init];
    
    __block OBJWavefrontObject *previousObject = nil;
    __block OBJWavefrontObject *currentObject = [[OBJWavefrontObject alloc] initWithObjectData:data];
    
    static const unichar OBJECT_DEFINITION = 'o';
    const NSRange CONTENTS_RANGE = NSMakeRange(0, contents.length);
    [contents enumerateSubstringsInRange:CONTENTS_RANGE
                                 options:NSStringEnumerationByLines
                              usingBlock:^(NSString *substring,
                                           NSRange substringRange,
                                           NSRange enclosingRange,
                                           BOOL *stop) {
                                  if (substringRange.length >= 3 && [substring characterAtIndex:0] == OBJECT_DEFINITION)
                                  {
                                      currentObject.name = [substring substringFromIndex:2]; // Assuming name starts here
                                      const NSUInteger location = NSMaxRange(enclosingRange); // Exclude current line
                                      currentObject.range = NSMakeRange(location, CONTENTS_RANGE.length - location);
                                      
                                      if (previousObject != nil)
                                      {
                                          NSRange previousRange = previousObject.range;
                                          previousRange.length = enclosingRange.location - previousRange.location; // Account for current line
                                          previousObject.range = previousRange;
                                      }
                                      
                                      OBJWavefrontObject *cachedObject = [cache cachedObjectForName:currentObject.name];
                                      OBJWavefrontObject *objectToAppend = (cachedObject ? cachedObject : currentObject);
                                      objectToAppend.file = self;
                                      [objects addObject:objectToAppend];
                                      previousObject = currentObject;
                                      currentObject = [[OBJWavefrontObject alloc] initWithObjectData:data];
                                  }
                              }];
    
    // The file itself is an un-named object
    // ie. there are no object definitions in the file
    if (objects.count == 0)
    {
        currentObject.range = CONTENTS_RANGE;
        
        OBJWavefrontObject *cachedObject = [cache cachedObjectForRootObject];
        OBJWavefrontObject *objectToAppend = (cachedObject ? cachedObject : currentObject);
        objectToAppend.file = self;
        [objects addObject:objectToAppend];
    }
    
    [objects enumerateObjectsWithOptions:NSEnumerationConcurrent
                              usingBlock:^(OBJWavefrontObject *obj, NSUInteger idx, BOOL *stop) {
                                  [obj complete];
                              }];
    
    return [objects copy];
}

@end

#pragma mark - OBJWavefrontObject Implementation

@implementation OBJWavefrontObject

@synthesize name = _name;
@synthesize range = _range;

- (instancetype)initWithObjectData:(NSData *)objectData
{
    self = [super init];
    if (self)
    {
        self->_objectData = objectData;
    }
    return self;
}

- (NSString *)contents
{
    NSData *objectData = self.objectData;
    NSAssert(objectData != nil, @"Object data cannot be nil");
    return [[NSString alloc] initWithBytesNoCopy:(void *)objectData.bytes
                                          length:objectData.length
                                        encoding:NSASCIIStringEncoding
                                    freeWhenDone:NO];
}

- (void)dealloc
{
    [self deallocateTemporaryBuffers]; // This should have already happened, but just want to be sure
}

#pragma mark Buffer properties

- (int)stride
{
    const int positionSize = self.positionSize;
    const int normalSize = self.normalSize;
    const int textureCoordSize = self.textureCoordSize;
    
    return sizeof(float) * (positionSize + normalSize + textureCoordSize);
}

- (int)positionSize
{
    return self->_positionSize;
}

- (int)normalSize
{
    return 3;
}

- (int)textureCoordSize
{
    return self->_texCoordSize;
}

- (const void *)positionOffset
{
    return OBJ_BUFFER_OFFSET(0);
}

- (const void *)normalOffset
{
    const int positionSize = self.positionSize;
    return OBJ_BUFFER_OFFSET(positionSize * sizeof(float));
}

- (const void *)textureCoordOffset
{
    const int positionSize = self.positionSize;
    const int normalSize = self.normalSize;
    return OBJ_BUFFER_OFFSET((positionSize + normalSize) * sizeof(float));
}

#pragma mark Parsing

- (void)complete
{
    [self parseInformation];
    
    [self allocateTemporaryBuffers];
    
    [self parseData];
    [self buildPackedBuffer];
    
    [self deallocateTemporaryBuffers];
    
    [self.file.cache cacheObject:self];
    
    self.objectData = nil;
}

- (void)parseInformation
{
    __block unsigned long positionCount = 0;
    __block unsigned long normalCount = 0;
    __block unsigned long textureCoordCount = 0;
    __block unsigned long faceCount = 0;
    
    __block unsigned int positionSize = 0;
    __block unsigned int texCoordSize = 0;
    __block unsigned int faceComponentCount = 0;
    
    [self enumerateLinesUsingBlock:^(NSString *line, OBJWavefrontLineDefinition definition) {
        switch (definition)
        {
            case OBJWavefrontVertexDefinition:{
                positionCount++;
                
                float lastComponent = 0.0f;
                unsigned int size = [self numberOfCoordinateComponentsInString:line lastComponent:&lastComponent];
                if (size == 4 && lastComponent == 1.0f)
                    size = 3;
                if (size > positionSize)
                    positionSize = size;
                
                break;
            }
            case OBJWavefrontNormalDefinition:
                normalCount++;
                break;
            case OBJWavefrontTextureCoordDefinition:{
                textureCoordCount++;
                
                float lastComponent = 0.0f;
                unsigned int size = [self numberOfCoordinateComponentsInString:line lastComponent:&lastComponent];
                if (size == 3 && lastComponent == 0.0f)
                    size = 2;
                if (size > texCoordSize)
                    texCoordSize = size;
                
                break;
            }
            case OBJWavefrontFaceDefinition:{
                faceCount++;
                
                unsigned int size = [self numberOfComponentsInFaceString:line];
                if (size > faceComponentCount)
                    faceComponentCount = size;
                
                break;
            }
            case OBJWavefrontUnknownDefinition:
            default:
                break;
        }
    }];
    
    self->_positionCount = positionCount;
    self->_normalCount = normalCount;
    self->_texCoordCount = textureCoordCount;
    self->_faceCount = faceCount;
    self->_positionSize = positionSize;
    self->_texCoordSize = texCoordSize;
    self->_faceComponentCount = faceComponentCount;
    self->_length = faceCount * faceComponentCount;
}

- (unsigned int)numberOfCoordinateComponentsInString:(NSString *)string lastComponent:(float *)lastComponent
{
    NSScanner *scanner = [NSScanner scannerWithString:string];
    
    NSCharacterSet *whitespaceSet = [NSCharacterSet whitespaceCharacterSet];
    scanner.charactersToBeSkipped = whitespaceSet;
    
    [scanner scanUpToCharactersFromSet:whitespaceSet intoString:nil]; // Scan past definition
    
    unsigned int componentCount = 0;
    float value;
    while ([scanner scanFloat:&value])
        componentCount++;
    
    if (lastComponent != NULL)
        *lastComponent = value;
    
    return componentCount;
}

- (unsigned int)numberOfComponentsInFaceString:(NSString *)string
{
    NSScanner *scanner = [NSScanner scannerWithString:string];
    scanner.charactersToBeSkipped = nil;
    
    NSCharacterSet *whitespaceSet = [NSCharacterSet whitespaceCharacterSet];
    
    [scanner scanUpToCharactersFromSet:whitespaceSet intoString:nil]; // Scan past definition
    [scanner scanCharactersFromSet:whitespaceSet intoString:nil];
    
    unsigned int componentCount = 0;
    while ([scanner scanUpToCharactersFromSet:whitespaceSet intoString:nil])
    {
        [scanner scanCharactersFromSet:whitespaceSet intoString:nil];
        componentCount++;
    }
    
    return componentCount;
}

#pragma mark Packed Buffer

- (void)parseData
{
    const unsigned int positionSize = self.positionSize;
    const unsigned int normalSize = self.normalSize;
    const unsigned int texCoordSize = self.textureCoordSize;
    const unsigned int faceComponentCount = self->_faceComponentCount;
    
    float *positionBuffer = self->_positionBuffer;
    float *normalBuffer = self->_normalBuffer;
    float *texCoordBuffer = self->_texCoordBuffer;
    int *faceIndexBuffer = self->_faceIndexBuffer;
    
    __block size_t positionIndex = 0;
    __block size_t normalIndex = 0;
    __block size_t texCoordIndex = 0;
    __block size_t faceIndex = 0;
    
    NSCharacterSet *whitespaceSet = [NSCharacterSet whitespaceCharacterSet];
    NSCharacterSet *decimalSet = [NSCharacterSet decimalDigitCharacterSet];
    [self enumerateLinesUsingBlock:^(NSString *line, OBJWavefrontLineDefinition definition) {
        if (definition != OBJWavefrontUnknownDefinition)
        {
            NSScanner *scanner = [[NSScanner alloc] initWithString:line];
            scanner.charactersToBeSkipped = whitespaceSet;
            [scanner scanUpToCharactersFromSet:whitespaceSet intoString:nil];
            [scanner scanCharactersFromSet:whitespaceSet intoString:nil];
            
            size_t i = 0;
            switch (definition)
            {
                case OBJWavefrontVertexDefinition:{
                    for (i = 0; i < positionSize; i++)
                        [scanner scanFloat:&positionBuffer[positionIndex + i]];
                    positionIndex += i;
                    break;
                }
                case OBJWavefrontNormalDefinition:{
                    for (i = 0; i < normalSize; i++)
                        [scanner scanFloat:&normalBuffer[normalIndex + i]];
                    normalIndex += i;
                    break;
                }
                case OBJWavefrontTextureCoordDefinition:{
                    for (i = 0; i < texCoordSize; i++)
                        [scanner scanFloat:&texCoordBuffer[texCoordIndex + i]];
                    texCoordIndex += i;
                    break;
                }
                case OBJWavefrontFaceDefinition:{
                    for (i = 0; i < faceComponentCount; i++)
                    {
                        int position = 0;
                        int textureCoord = 0;
                        int normal = 0;
                        
                        [scanner scanInt:&position], scanner.scanLocation += 1;
                        
                        if ([scanner scanInt:&textureCoord])
                            scanner.scanLocation += 1;
                        else
                            [scanner scanUpToCharactersFromSet:decimalSet intoString:nil];
                        
                        [scanner scanInt:&normal];
                        
                        faceIndexBuffer[faceIndex++] = position;
                        faceIndexBuffer[faceIndex++] = normal;
                        faceIndexBuffer[faceIndex++] = textureCoord;
                    }
                }
                default:
                    break;
            }
        }
    }];
}

- (void)buildPackedBuffer
{
    const int positionSize = self.positionSize;
    const int normalSize = self.normalSize;
    const int textureCoordSize = self.textureCoordSize;
    const unsigned int faceComponentCount = self->_faceComponentCount;
//    const unsigned int faceComponentCount = 3; // v1/vn1/vt1
    const unsigned int faceIndexSize = 3 * faceComponentCount; // I've forgetten what 3 is
    const size_t faceSize = faceComponentCount * (positionSize + normalSize + textureCoordSize) * sizeof(float); // Size of one face in bytes
    const unsigned long faceCount = self->_faceCount;
    const size_t bufferLength = faceSize * faceCount;
    
    const float *positionBuffer = self->_positionBuffer;
    const float *normalBuffer = self->_normalBuffer;
    const float *texCoordBuffer = self->_texCoordBuffer;
    const int *faceIndexBuffer = self->_faceIndexBuffer;
    
    float *buffer = calloc(bufferLength, sizeof(float));
    
    size_t b, f; // Buffer Index, Face Index
    for (b = 0, f = 0; b < bufferLength && f < (faceIndexSize * faceCount);)
    {
        size_t facePositionOffset = faceIndexBuffer[f++] - 1;
        for (int v = 0; v < positionSize; v++)
        {
            buffer[b++] = positionBuffer[(facePositionOffset * positionSize) + v];
        }
        
        size_t faceNormalOffset = faceIndexBuffer[f++] - 1;
        for (int v = 0; v < normalSize; v++)
        {
            buffer[b++] = normalBuffer[(faceNormalOffset * normalSize) + v];
        }
        
        size_t faceTextureOffset = faceIndexBuffer[f++] - 1;
        for (int v = 0; v < textureCoordSize; v++)
        {
            buffer[b++] = texCoordBuffer[(faceTextureOffset * textureCoordSize) + v];
        }
    }
    
    self->_buffer = [NSData dataWithBytesNoCopy:buffer length:bufferLength freeWhenDone:YES];
}

#pragma mark Temporary Buffers

- (void)allocateTemporaryBuffers
{
    const unsigned long positionCount = self->_positionCount;
    const unsigned long normalCount = self->_normalCount;
    const unsigned long textureCoordCount = self->_texCoordCount;
    const unsigned long faceCount = self->_faceCount;
    
    const unsigned int positionSize = self.positionSize;
    const unsigned int normalSize = self.normalSize;
    const unsigned int texCoordSize = self.textureCoordSize;
    const unsigned int faceComponentCount = self->_faceComponentCount;
    const unsigned int faceIndexSize = 3 * faceComponentCount;
    
    const size_t positionBufferSize = sizeof(float) * positionSize * positionCount;
    const size_t normalBufferSize = sizeof(float) * normalSize * normalCount;
    const size_t texCoordBufferSize = sizeof(float) * texCoordSize * textureCoordCount;
    const size_t faceIndexBufferSize = sizeof(int) * faceIndexSize * faceCount;
    
    self->_positionBuffer = calloc(1, positionBufferSize);
    self->_normalBuffer = calloc(1, normalBufferSize);
    self->_texCoordBuffer = calloc(1, texCoordBufferSize);
    self->_faceIndexBuffer = calloc(1, faceIndexBufferSize);
}

- (void)deallocateTemporaryBuffers
{
    free(self->_positionBuffer), self->_positionBuffer = NULL;
    free(self->_normalBuffer), self->_normalBuffer = NULL;
    free(self->_texCoordBuffer), self->_texCoordBuffer = NULL;
    free(self->_faceIndexBuffer), self->_faceIndexBuffer = NULL;
}

#pragma mark Convenience Methods

- (void)enumerateLinesUsingBlock:(void (^)(NSString *line, OBJWavefrontLineDefinition definition))block
{
    if (block == nil)
        return;
    
    static const unichar VERTEX_DEFINITION = 'v'; // v
    static const unichar NORMAL_DEFINITION = 'n'; // vn
    static const unichar TEXTURE_COORD_DEFINITION = 't'; // vt
    static const unichar FACE_DEFINITION = 'f'; // f
    
    NSString *contents = self.contents;
    [contents enumerateSubstringsInRange:self.range
                                 options:NSStringEnumerationByLines
                              usingBlock:^(NSString *substring,
                                           NSRange substringRange,
                                           NSRange enclosingRange,
                                           BOOL *stop) {
                                  if (substringRange.length >= IDENTIFIER_LENGTH)
                                  {
                                      OBJWavefrontLineDefinition definition = OBJWavefrontUnknownDefinition;
                                      
                                      unichar identifier[IDENTIFIER_LENGTH] = { '\0' };
                                      [substring getCharacters:identifier range:NSMakeRange(0, IDENTIFIER_LENGTH)];
                                      
                                      if (identifier[0] == VERTEX_DEFINITION)
                                      {
                                          if (identifier[1] == NORMAL_DEFINITION)
                                          {
                                              definition = OBJWavefrontNormalDefinition;
                                          }
                                          else if (identifier[1] == TEXTURE_COORD_DEFINITION)
                                          {
                                              definition = OBJWavefrontTextureCoordDefinition;
                                          }
                                          else // Just a plain ol' vertex
                                          {
                                              definition = OBJWavefrontVertexDefinition;
                                          }
                                      }
                                      else if (identifier[0] == FACE_DEFINITION)
                                      {
                                          definition = OBJWavefrontFaceDefinition;
                                      }
                                      
                                      block(substring, definition);
                                  }
                              }];
}

@end

#pragma mark - OBJWavefrontCache Implementation

@implementation OBJWavefrontCache

- (instancetype)init
{
    return [self initWithCacheName:nil error:nil];
}

- (instancetype)initWithFileAtPath:(NSString *)path options:(OBJWavefrontCacheOptions)options error:(NSError **)error
{
    NSParameterAssert(path != nil);
    
    NSString *cacheKey = [[self class] cacheKeyWithFileAtPath:path options:options];
    
    return [self initWithCacheName:cacheKey error:error];
}

- (instancetype)initWithCacheName:(NSString *)name error:(NSError **)error
{
    return [self initWithCacheName:name options:OBJWavefrontCacheLoadMappedData error:nil];
}

- (instancetype)initWithCacheName:(NSString *)name options:(OBJWavefrontCacheOptions)options error:(NSError **)error
{
    NSParameterAssert(name != nil);
    
    self = [super init];
    if (self)
    {
        self.enabled = YES;
        
        self->_name = name;
        
        self->_options = options;
        
        NSString *cacheDir = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
        if ([[NSFileManager defaultManager] createDirectoryAtPath:cacheDir withIntermediateDirectories:YES attributes:nil error:error] == NO)
            return (self = nil);
        
        self->_cachePath = cacheDir;
    }
    return self;
}

+ (NSString *)cacheKeyWithFileAtPath:(NSString *)path options:(OBJWavefrontCacheOptions)options
{
    #if OBJWavefrontCacheUsesCommonCrypto
        CC_SHA1_CTX ctx;
        CC_SHA1_Init(&ctx);
    
        #define OBJ_CACHE_PATH_ENCODING NSUTF8StringEncoding
    
        if ((options & OBJWavefrontCacheHashUsingFileContents) == OBJWavefrontCacheHashUsingFileContents)
        {
            int fd = open([path cStringUsingEncoding:OBJ_CACHE_PATH_ENCODING], O_RDONLY);
    
            if (fd == -1)
            {
                CC_SHA1_Update(&ctx, [path cStringUsingEncoding:NSUTF8StringEncoding], (CC_LONG)path.length);
            }
            else
            {
                #define OBJ_CACHE_BUFFER_SIZE 512
                unsigned char buffer[OBJ_CACHE_BUFFER_SIZE];
        
                ssize_t bytesRead = 0;
                while ((bytesRead = read(fd, buffer, OBJ_CACHE_BUFFER_SIZE)) != 0)
                    CC_SHA1_Update(&ctx, buffer, (CC_LONG)bytesRead);
            }
            
            close(fd);
        }
        else
        {
            CC_SHA1_Update(&ctx, [path cStringUsingEncoding:OBJ_CACHE_PATH_ENCODING], (CC_LONG)path.length);
        }
    
        unsigned char digest[CC_SHA1_DIGEST_LENGTH];
        CC_SHA1_Final(digest, &ctx);
    
        unichar *hexCharacters = malloc(sizeof(unichar) * (CC_SHA1_DIGEST_LENGTH * 2));
        static const char lookup[] = { '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f' };
        
        size_t j = 0;
        for (size_t i = 0; i < CC_SHA1_DIGEST_LENGTH; i++)
        {
            unsigned char digestByte = digest[i];
            hexCharacters[j++] = lookup[(digestByte & 0xF0) >> 4];
            hexCharacters[j++] = lookup[(digestByte & 0x0F)];
        }
    
        NSString *hexString = [[NSString alloc] initWithCharactersNoCopy:hexCharacters length:(2 * CC_SHA1_DIGEST_LENGTH) freeWhenDone:YES];
        return hexString;
    #else
    return [path lastPathComponent];
    #endif
}

+ (NSString *)cacheKeyForString:(NSString *)string
{
#if OBJWavefrontCacheUsesCommonCrypto
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1([string UTF8String], (CC_LONG)string.length, digest);
    
    unichar *hexCharacters = malloc(sizeof(unichar) * (CC_SHA1_DIGEST_LENGTH * 2));
    static const char lookup[] = { '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f' };
    
    size_t j = 0;
    for (size_t i = 0; i < CC_SHA1_DIGEST_LENGTH; i++)
    {
        unsigned char digestByte = digest[i];
        hexCharacters[j++] = lookup[(digestByte & 0xF0) >> 4];
        hexCharacters[j++] = lookup[(digestByte & 0x0F)];
    }
    
    NSString *hexString = [[NSString alloc] initWithCharactersNoCopy:hexCharacters length:(2 * CC_SHA1_DIGEST_LENGTH) freeWhenDone:YES];
    return hexString;
#else
    return string;
#endif
}

- (OBJWavefrontObject *)cachedObjectForRootObject
{
    return [self cachedObjectForKey:OBJWavefrontCacheRootObjectName];
}

- (OBJWavefrontObject *)cachedObjectForName:(NSString *)name
{
    if ([self isEnabled] == NO || name == nil)
        return nil;
    
    NSString *key = [[self class] cacheKeyForString:name];
    return [self cachedObjectForKey:key];
}

- (OBJWavefrontObject *)cachedObjectForKey:(NSString *)key
{
    if (key == nil)
        return nil;
    
    NSString *path = [self.cachePath stringByAppendingPathComponent:key];
    BOOL isDirectory = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] == NO || isDirectory == YES)
        return nil;
    
    NSData *objectData = nil;
    if ((self.options & OBJWavefrontCacheLoadMappedData) == OBJWavefrontCacheLoadMappedData)
        objectData = [[OBJMappedData alloc] initWithContentsOfFile:path];
    else
        objectData = [[NSData alloc] initWithContentsOfFile:path options:0 error:nil];
    
    return [[OBJWavefrontCachedObject alloc] initWithObjectData:objectData];
}

- (BOOL)cacheObject:(OBJWavefrontObject *)object
{
    if (object == nil)
        return NO;
    
    NSString *key = object.name;
    if (key != nil)
        key = [[self class] cacheKeyForString:key];
    else
        key = OBJWavefrontCacheRootObjectName;
    
    return [self cacheObject:object forKey:key];
}

- (BOOL)cacheObject:(OBJWavefrontObject *)object forKey:(NSString *)key
{
    if ([self isEnabled] == NO || key == nil)
        return NO;
    
    NSString *path = [self.cachePath stringByAppendingPathComponent:key];
    
    return [object writeToFile:path];
}

- (BOOL)removeAllObjects:(NSError **)error
{
    NSFileManager *fm = [[NSFileManager alloc] init];
    
    NSURL *cacheURL = [NSURL fileURLWithPath:self.cachePath];
    
    NSArray *files = [fm contentsOfDirectoryAtURL:cacheURL includingPropertiesForKeys:nil options:0 error:error];
    if (files == nil)
        return NO;
    
    BOOL success = YES;
    for (NSURL *fileURL in files)
    {
        if ([fm removeItemAtURL:fileURL error:error] == NO)
        {
            success = NO;
            break;
        }
    }
    return YES;
}

@end

@implementation OBJWavefrontObject (Caching)

- (BOOL)writeToFile:(NSString *)path
{
    NSFileManager *fm = [[NSFileManager alloc] init];
    if ([fm fileExistsAtPath:path] == NO)
        [fm createFileAtPath:path contents:nil attributes:nil];
    
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:path];
    
    NSData *metadata = [self archiveMetadata];
    
    NSString *lengthString = [NSString stringWithFormat:@"%lu", (unsigned long)metadata.length];
    NSString *lengthLengthString = [NSString stringWithFormat:@"%02lu", (unsigned long)lengthString.length]; // Don't change this format string otherwise the universe will implode
    NSData *lengthData = [lengthString dataUsingEncoding:NSUTF8StringEncoding];
    NSData *lengthLengthData = [lengthLengthString dataUsingEncoding:NSUTF8StringEncoding];
    
    // Format (minus comment line breaks):
    // <length of length string: 2 decimal digit number for length of next component>
    // <length of metadata: decimal digit number>
    // <metadata>
    // <packed data>
    
    [fileHandle writeData:lengthLengthData];
    [fileHandle writeData:lengthData];
    [fileHandle writeData:metadata];
    [fileHandle writeData:self.buffer];
    
    [fileHandle synchronizeFile];
    [fileHandle closeFile];
    
    return YES;
}

- (NSData *)archiveMetadata
{
    NSMutableData *metadata = [[NSMutableData alloc] init];
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:metadata];
    
    // [archiver encodeInt:self.stride forKey:@"stride"];
    // stride is calculated from the below
    [archiver encodeInt:self.positionSize forKey:@"positionSize"];
    // [archiver encodeInt:self.normalSize forKey:@"normalSize"];
    [archiver encodeInt:self.textureCoordSize forKey:@"textureCoordSize"];
    
    // [archiver encodeInt:(int)self.vertexOffset forKey:@"vertexOffset"];
    // [archiver encodeInt:(int)self.normalOffset forKey:@"normalOffset"];
    // [archiver encodeInt:(int)self.textureCoordOffset forKey:@"textureCoordOffset"];
    
    [archiver encodeInt64:self->_length forKey:@"length"];
    
    [archiver finishEncoding];
    
    return metadata;
}

- (void)unarchiveMetadata:(NSData *)data
{
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
    
    // [unarchiver decodeIntForKey:@"stride"];
    // stride is calculated from the below
    self->_positionSize = [unarchiver decodeIntForKey:@"positionSize"];
    // [unarchiver decodeIntForKey:@"normalSize"];
    self->_texCoordSize = [unarchiver decodeIntForKey:@"textureCoordSize"];
    
    self->_length = (unsigned long)[unarchiver decodeInt64ForKey:@"length"];
    
    [unarchiver finishDecoding];
}

@end

@implementation OBJWavefrontCachedObject

- (instancetype)initWithObjectData:(NSData *)data
{
    NSParameterAssert(data != nil);
    
    self = [super initWithObjectData:nil];
    if (self)
    {
        NSData *lengthLengthData = [data subdataWithRange:NSMakeRange(0, 2)]; // Don't change this length
        NSString *lengthLengthString = [[NSString alloc] initWithData:lengthLengthData encoding:NSUTF8StringEncoding];
        int lengthLength = [lengthLengthString intValue];
        
        const NSRange metaLengthRange = NSMakeRange(2, lengthLength);
        NSData *metaLengthData = [data subdataWithRange:metaLengthRange];
        NSString *metaLengthString = [[NSString alloc] initWithData:metaLengthData encoding:NSUTF8StringEncoding];
        NSUInteger metadataLength = [metaLengthString integerValue];
        
        const NSRange metadataRange = NSMakeRange(NSMaxRange(metaLengthRange), metadataLength);
        NSData *metadata = [data subdataWithRange:metadataRange];
        [self unarchiveMetadata:metadata];
        
        const NSUInteger dataLocation = NSMaxRange(metadataRange);
        const NSUInteger dataLength = data.length - dataLocation;
        self->_buffer = [data subdataWithRange:NSMakeRange(dataLocation, dataLength)];
    }
    return self;
}

#pragma mark OBJWavefrontObject

- (NSData *)objectData
{
    return nil;
}

- (NSString *)contents
{
    return nil;
}

- (void)complete
{
    // [super complete];
}

@end

@implementation OBJMappedData

- (instancetype)initWithContentsOfFile:(NSString *)path
{
    self = [super init];
    if (self)
    {
        NSFileManager *fm = [[NSFileManager alloc] init];
        NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
        NSNumber *fileSize = [attrs objectForKey:NSFileSize];
        if (fileSize == nil)
            return (self = nil);
        
        NSUInteger length = [fileSize unsignedIntegerValue];
        
        int fd = open([path UTF8String], O_RDONLY);
        if (fd == -1)
            return (self = nil);
        
        NSFileHandle *fileHandle = [[NSFileHandle alloc] initWithFileDescriptor:fd closeOnDealloc:YES];
        
        self = [self initWithFileHandle:fileHandle length:length];
    }
    return self;
}

- (instancetype)initWithFileHandle:(NSFileHandle *)fileHandle length:(NSUInteger)length
{
    return [self initWithFileHandle:fileHandle length:length range:NSMakeRange(0, length)];
}

- (instancetype)initWithFileHandle:(NSFileHandle *)fileHandle length:(NSUInteger)length range:(NSRange)range
{
    self = [super init];
    if (self)
    {
        if (fileHandle == nil || length == 0 || NSMaxRange(range) > length || range.length == 0)
            return (self = nil);
        
        self->_length = range.length;
        self->_fileHandle = fileHandle;
        
        int fd = [fileHandle fileDescriptor];
        void *bytes = mmap(NULL, self->_length, PROT_READ, MAP_PRIVATE | MAP_FILE, fd, 0);
        if (bytes == MAP_FAILED)
            return (self = nil);
        
        self->_mappedBytes = bytes;
        self->_bytes = (uint8_t *)bytes + range.location;
    }
    return self;
}

- (void)dealloc
{
    munmap(self->_mappedBytes, self->_length);
}

#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone
{
    return [NSData dataWithBytes:self.bytes length:self.length];
}

- (id)mutableCopyWithZone:(NSZone *)zone
{
    return [NSMutableData dataWithBytes:self.bytes length:self.length];
}

#pragma mark Subdata

- (NSData *)subdataWithRange:(NSRange)range
{
    if (NSMaxRange(range) > self.length)
        return nil;
    
    return [[OBJMappedData alloc] initWithFileHandle:self.fileHandle length:self.length range:range];
}

#pragma mark NSData

- (const void *)bytes
{
    return self->_bytes;
}

- (NSUInteger)length
{
    return self->_length;
}

@end
