//
//  OBJWavefrontTests.m
//  OBJWavefrontTests
//
//  Created by Nathan Wood on 16/03/2014.
//  Copyright (c) 2014 Nathan Wood. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "OBJWavefrontFile.h"

@interface OBJWavefrontTests : XCTestCase

@end

@implementation OBJWavefrontTests

- (void)testPlaneFile
{
    NSString *path = [[NSBundle bundleForClass:[self class]] pathForResource:@"plane" ofType:@"obj"];
    XCTAssertNotNil(path, @"plane.obj required for testing");
    
    OBJWavefrontFile *file = [[OBJWavefrontFile alloc] initWithContentsOfFile:path cache:nil];
    XCTAssertNotNil(file, @"File should not be nil");
    XCTAssertNil(file.cache, @"Cache should be nil");
    
    NSError *error = nil;
    NSArray *objects = [file objectsWithError:&error];
    XCTAssertNil(error, @"Error should be nil");
    
    XCTAssertEqual((NSUInteger)objects.count, (NSUInteger)1, @"File only contains one object definition");
}

- (void)testPlaneObject
{
    NSString *path = [[NSBundle bundleForClass:[self class]] pathForResource:@"plane" ofType:@"obj"];
    OBJWavefrontFile *file = [[OBJWavefrontFile alloc] initWithContentsOfFile:path cache:nil];
    OBJWavefrontObject *object = [file.objects objectAtIndex:0];
    
    XCTAssertEqual((NSUInteger)object.length, (NSUInteger)6, @"Plane is made up of 2 triangles, so 6 points");
    
    XCTAssertEqual((int)object.stride, (int)32, @"Tex coord's 3rd value is 0.0 so it's ignored, totaling 8 floats, 32 bytes");
    
    XCTAssertEqual((int)object.positionSize, (int)3, @"Position is made up of 3 floats");
    XCTAssertEqual((int)object.normalSize, (int)3, @"Position is made up of 3 floats");
    XCTAssertEqual((int)object.textureCoordSize, (int)2, @"Position is made up of 2 floats, last one from file is ignored");
}

@end
