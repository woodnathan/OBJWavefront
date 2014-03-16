//
//  OBJWavefrontFile.h
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

#import <Foundation/Foundation.h>

/**
 *  If CommonCrypto is not used it falls back to using the filename
 */
#ifndef OBJWavefrontCacheUsesCommonCrypto
#define OBJWavefrontCacheUsesCommonCrypto 1 // Uses hashing to determine cache object
#endif

__unused extern NSString *const OBJWavefrontErrorDomain;

typedef NS_ENUM(NSUInteger, OBJWavefrontCacheOptions) {
    OBJWavefrontCacheOptionsNone = 0,
    /**
     *  Uses mmap to load objects from disk
     */
    OBJWavefrontCacheLoadMappedData = 1 << 1,
    /**
     *  Hashes the Wavefront .obj contents for the cache name, or the file path
     *  Useful if the contents of the file change
     */
    OBJWavefrontCacheHashUsingFileContents = 1 << 2
};

@class OBJWavefrontCache;

/**
 *  A Wavefront .obj file
 */
@interface OBJWavefrontFile : NSObject

/**
 *  Initializes a OBJWavefrontFile with the specified file path and the default
 *  cache for the file
 *
 *  @param file The path to the Wavefront .obj file
 *
 *  @return A OBJWavefrontFile instance with a cache
 */
- (instancetype)initWithContentsOfFile:(NSString *)file;

/**
 *  Initializes a OBJWavefrontFile with the specified file path and the default
 *  cache for the file
 *
 *  @param file  The path to the Wavefront .obj file
 *  @param error Any error that occurred during initializing the cache
 *
 *  @return A OBJWavefrontFile instance with a cache
 */
- (instancetype)initWithContentsOfFile:(NSString *)file error:(NSError *__autoreleasing *)error;

/**
 *  Initializes a OBJWavefrontFile with the specified file path and the default
 *  cache for the file
 *
 *  @param file    The path to the Wavefront .obj file
 *  @param options Options for the cache
 *  @param error   Any error that occurred during initializing the cache
 *
 *  @return A OBJWavefrontFile instance with a cache
 */
- (instancetype)initWithContentsOfFile:(NSString *)file options:(OBJWavefrontCacheOptions)options error:(NSError *__autoreleasing *)error;

/**
 *  The designated initializer
 *
 *  @param file  The path to the Wavefront .obj file
 *  @param cache The cache to use, specify nil to disable caching
 *
 *  @return A OBJWavefrontFile instance with the specified cache
 */
- (instancetype)initWithContentsOfFile:(NSString *)file cache:(OBJWavefrontCache *)cache;

/**
 *  Initializes a OBJWavefrontFile with data
 *
 *  @param data  A data object representing the Wavefront .obj file
 *  @param cache The cache to use, specify nil to disable caching
 *
 *  @return A OBJWavefrontFile instance with the specified cache
 */
- (instancetype)initWithData:(NSData *)data cache:(OBJWavefrontCache *)cache;

/**
 *  The OBJWavefrontCache disk cache
 */
@property (nonatomic, readonly) OBJWavefrontCache *cache;

/**
 *  An array of OBJWavefrontObject instances
 *  Note: This is lazily evaluated if initialized with a file path
 */
@property (nonatomic, readonly) NSArray *objects;

- (NSArray *)objectsWithError:(NSError *__autoreleasing *)error;

@end

/**
 *  An object inside a obj file
 */
@interface OBJWavefrontObject : NSObject

/**
 *  The name of the object, or nil if there is no name
 */
@property (nonatomic, copy, readonly) NSString *name;

/**
 *  The range of the bytes in the obj file
 */
@property (nonatomic, assign, readonly) NSRange range;

/**
 *  Buffer Information
 *  Packed in the following order:
 *    - Vertex (xyz / xyzw)
 *    - Normal (xyz)
 *    - Texture (uv / uvw)
 *  
 *  Example:
 *    glVertexAttribPointer(GLKVertexAttribPosition, obj.positionSize, GL_FLOAT, GL_FALSE, obj.stride, obj.positionOffset);
 *    glVertexAttribPointer(GLKVertexAttribNormal, obj.normalSize, GL_FLOAT, GL_FALSE, obj.stride, obj.normalOffset);
 *    glVertexAttribPointer(GLKVertexAttribTexCoord0, obj.textureCoordSize, GL_FLOAT, GL_FALSE, obj.stride, obj.textureCoordOffset);
 */
@property (nonatomic, readonly) int stride;

/**
 *  Size of the position attribute in number of components: x, y, z
 */
@property (nonatomic, readonly) int positionSize;

/**
 *  Size of the position attribute in number of components: x, y, z
 */
@property (nonatomic, readonly) int normalSize;

/**
 *  Size of the position attribute in number of components: u, v
 */
@property (nonatomic, readonly) int textureCoordSize;

/**
 *  Offset of the position coordinates in the buffer in number of bytes
 */
@property (nonatomic, readonly) const void *positionOffset;

/**
 *  Offset of the normal vector in the buffer in number of bytes
 */
@property (nonatomic, readonly) const void *normalOffset;

/**
 *  Offset of the texture coordinates in the buffer in number of bytes
 */
@property (nonatomic, readonly) const void *textureCoordOffset;

/**
 *  The packed bytes to pass into an array buffer
 *  See Buffer Information above for more information
 *
 *  Example:
 *    glBufferData(GL_ARRAY_BUFFER, data.length, data.bytes, GL_STATIC_DRAW);
 */
@property (nonatomic, readonly) NSData *buffer;

/**
 *  The length of GL_ARRAY_BUFFER
 *  Note: This is not in bytes, use data.length
 *  
 *  Example:
 *    glDrawArrays(GL_TRIANGLES, object.length);
 */
@property (nonatomic, readonly) NSUInteger length;

@end

/**
 *  Provides a mechanism for caching a file's objects on disk
 *  Note that this is not endian-safe
 */
@interface OBJWavefrontCache : NSObject

/**
 *  A cache with options of OBJWavefrontCacheMappedData
 *
 *  @param name  The name of the cache (Required)
 *  @param error An error that may be encountered
 *
 *  @return A OBJWavefrontCache instance, or nil if an error occurred
 */
- (instancetype)initWithCacheName:(NSString *)name error:(NSError **)error;

/**
 *  The designated initializer
 *
 *  @param name    The name of the cache (Required)
 *  @param options The options for the cache
 *  @param error   An error that may be encountered
 *
 *  @return A OBJWavefrontCache instance, or nil if an error occurred
 */
- (instancetype)initWithCacheName:(NSString *)name options:(OBJWavefrontCacheOptions)options error:(NSError *__autoreleasing *)error;

/**
 *  The name of the cache
 */
@property (nonatomic, readonly) NSString *name;

/**
 *  The cache options
 */
@property (nonatomic, readonly) OBJWavefrontCacheOptions options;

/**
 *  Cache can be enabled or disabled
 */
@property (nonatomic, assign, getter = isEnabled) BOOL enabled;

/**
 *  Gets the cached object for the default (unnamed) object
 *
 *  @return A OBJWavefrontObject instance, or nil if it's not found in the cache
 */
- (OBJWavefrontObject *)cachedObjectForRootObject;

/**
 *  Gets the cached object for the provided name
 *
 *  @param name The name of the Wavefront object
 *
 *  @return A OBJWavefrontObject instance, or nil if it's not found in the cache
 */
- (OBJWavefrontObject *)cachedObjectForName:(NSString *)name;

/**
 *  Gets the cached object for the provided key
 *
 *  @param key The key of the item in the cache
 *
 *  @return A OBJWavefrontObject instance, or nil if it's not found in the cache
 */
- (OBJWavefrontObject *)cachedObjectForKey:(NSString *)key;

/**
 *  Caches the provided object using it's name or
 *  as the default object if it does not have a name
 *
 *  @param object The object to be cached
 *
 *  @return YES if the object was cached, otherwise NO
 */
- (BOOL)cacheObject:(OBJWavefrontObject *)object;

/**
 *  Caches the provided object using the key provided
 *
 *  @param key The key to identify the object in the cache
 *
 *  @return YES if the object was cached, otherwise NO
 */
- (BOOL)cacheObject:(OBJWavefrontObject *)object forKey:(NSString *)key;

/**
 *  Empties the cache
 */
- (BOOL)removeAllObjects:(NSError **)error;

@end

/**
 *  This NSData subclass is used by the cache to reduce the amount of data
 *  in memory
 *  Copying this object returns an unmapped data object (immutable or mutable)
 */
@interface OBJMappedData : NSData

- (instancetype)initWithContentsOfFile:(NSString *)path;

@end

