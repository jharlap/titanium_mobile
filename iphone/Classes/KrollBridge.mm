/**
 * Appcelerator Titanium Mobile
 * Copyright (c) 2009-2010 by Appcelerator, Inc. All Rights Reserved.
 * Licensed under the terms of the Apache Public License
 * Please see the LICENSE included with this distribution for details.
 */

#import "KrollBridge.h"
#import "KrollCallback.h"
#import "KrollObject.h"
#import "TiHost.h"
#import "TitaniumModule.h"
#import "TiUtils.h"
#import "TitaniumApp.h"

@implementation TitaniumObject

-(id)initWithContext:(KrollContext*)context_ host:(TiHost*)host_
{
	if (self = [super initWithTarget:[[[TitaniumModule alloc] init] autorelease] context:context_])
	{
		modules = [[NSMutableDictionary alloc] init];
		host = [host_ retain];
		
		// pre-cache a few modules we always use
		TiModule *ui = [host moduleNamed:@"UI"];
		[self addModule:@"UI" module:ui];
	}
	return self;
}

#if KROLLBRIDGE_MEMORY_DEBUG==1
-(id)retain
{
	NSLog(@"RETAIN: %@ (%d)",self,[self retainCount]+1);
	return [super retain];
}
-(oneway void)release 
{
	NSLog(@"RELEASE: %@ (%d)",self,[self retainCount]-1);
	[super release];
}
#endif

-(void)dealloc
{
	RELEASE_TO_NIL(host);
	RELEASE_TO_NIL(modules);
	[super dealloc];
}

-(void)gc
{
	[modules removeAllObjects];
	[properties removeAllObjects];
}

-(id)valueForKey:(NSString *)key
{
	id module = [modules objectForKey:key];
	if (module!=nil)
	{
		return module;
	}
	module = [host moduleNamed:key];
	if (module!=nil)
	{
		return [self addModule:key module:module];
	}
	//go against module
	return [super valueForKey:key];
}

-(void)setValue:(id)value forKey:(NSString *)key
{
	// can't delete at the Titanium level so no-op
}

-(KrollObject*)addModule:(NSString*)name module:(TiModule*)module
{
	KrollObject *ko = [[[KrollObject alloc] initWithTarget:module context:context] autorelease];
	[modules setObject:ko forKey:name];
	return ko;
}

-(TiModule*)moduleNamed:(NSString*)name
{
	return [modules objectForKey:name];
}
@end


@implementation KrollBridge

-(id)init
{
	if (self = [super init])
	{
#if KROLLBRIDGE_MEMORY_DEBUG==1
		NSLog(@"INIT: %@",self);
#endif
	}
	return self;
}

#if KROLLBRIDGE_MEMORY_DEBUG==1
-(id)retain
{
	NSLog(@"RETAIN: %@ (%d)",self,[self retainCount]+1);
	return [super retain];
}
-(oneway void)release 
{
	NSLog(@"RELEASE: %@ (%d)",self,[self retainCount]-1);
	[super release];
}
#endif

-(void)dealloc
{
#if KROLLBRIDGE_MEMORY_DEBUG==1
	NSLog(@"DEALLOC: %@",self);
#endif
	RELEASE_TO_NIL(preload);
	RELEASE_TO_NIL(context);
	RELEASE_TO_NIL(titanium);
	[super dealloc];
}

- (TiHost*)host
{
	return host;
}

- (KrollContext*) krollContext
{
	return context;
}

- (id)preloadForKey:(id)key
{
	if (preload!=nil)
	{
		return [preload objectForKey:key];
	}
	return nil;
}

- (void)boot:(id)callback url:(NSURL*)url_ preload:(NSDictionary*)preload_
{
	preload = [preload_ retain];
	[super boot:callback url:url_ preload:preload_];
	context = [[KrollContext alloc] init];
	context.delegate = self;
	[context start];
}

- (void)evalJS:(NSString*)code
{
	[context evalJS:code];
}

- (void)scriptError:(NSString*)message
{
	[[TitaniumApp app] showModalError:message];
	/*
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Script Error" message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
	[alert show];
	[alert autorelease];*/
}

- (void)evalFileOnThread:(NSString*)path context:(KrollContext*)context_ 
{
	NSError *error = nil;
	TiValueRef exception = NULL;
	
	TiContextRef jsContext = [context_ context];
	 
	NSURL *url_ = [path hasPrefix:@"file:"] ? [NSURL URLWithString:path] : [NSURL fileURLWithPath:path];
	
	if (![path hasPrefix:@"/"] && ![path hasPrefix:@"file:"])
	{
		NSURL *root = [host baseURL];
		url_ = [NSURL fileURLWithPath:[NSString stringWithFormat:@"%@/%@",root,path]];
	}

	NSString *jcode = [NSString stringWithContentsOfURL:url_ encoding:NSUTF8StringEncoding error:&error];
	if (error!=nil)
	{
		NSLog(@"[ERROR] error loading path: %@, %@",path,error);
		[self scriptError:[NSString stringWithFormat:@"Error loading script %@. %@",[path lastPathComponent],[error description]]];
		return;
	}

	NSMutableString *code = [[NSMutableString alloc] init];
	[code appendString:jcode];

	TiStringRef jsCode = TiStringCreateWithUTF8CString([code UTF8String]);
	TiStringRef jsURL = TiStringCreateWithUTF8CString([[url_ absoluteString] UTF8String]);

	// validate script
	// TODO: we do not need to do this in production app
	if (!TiCheckScriptSyntax(jsContext,jsCode,jsURL,1,&exception))
	{
		id excm = [KrollObject toID:context value:exception];
		NSLog(@"[ERROR] Syntax Error = %@",[TiUtils exceptionMessage:excm]);
		[self scriptError:[TiUtils exceptionMessage:excm]];
	}
	
	// only continue if we don't have any exceptions from above
	if (exception == NULL)
	{
		TiEvalScript(jsContext, jsCode, NULL, jsURL, 1, &exception);
		
		if (exception!=NULL)
		{
			id excm = [KrollObject toID:context value:exception];
			NSLog(@"[ERROR] Script Error = %@.",[TiUtils exceptionMessage:excm]);
			[self scriptError:[TiUtils exceptionMessage:excm]];
		}
	}

	[code release];
	TiStringRelease(jsCode);
	TiStringRelease(jsURL);
}

- (void)evalFile:(NSString*)path condition:(NSCondition*)condition
{
	[context invokeOnThread:self method:@selector(evalFileOnThread:context:) withObject:path condition:condition];
}

- (void)evalFile:(NSString*)path callback:(id)callback selector:(SEL)selector
{
	[context invokeOnThread:self method:@selector(evalFileOnThread:context:) withObject:path callback:callback selector:selector];
}

- (void)evalFile:(NSString *)file
{
	[self evalFile:file condition:nil];
}

- (void)fireEvent:(id)listener withObject:(id)obj remove:(BOOL)yn thisObject:(TiProxy*)thisObject_
{
	if ([listener isKindOfClass:[KrollCallback class]])
	{
		[context invokeEvent:listener args:[NSArray arrayWithObject:obj] thisObject:thisObject_];
	}
	else 
	{
		NSLog(@"[ERROR] listener callback is of a non-supported type: %@",[listener class]);
	}

}

-(void)injectPatches
{
	// called to inject any Titanium patches in JS before a context is loaded... nice for 
	// setting up backwards compat type APIs
	
	NSMutableString *js = [[[NSMutableString alloc] init] autorelease];
	
	[js appendString:@"Ti.UI.iPhone.createGroupedSection = function(a,b,c){ return Ti.UI.createGroupedSection(a,b,c); };"];
	[js appendString:@"Ti.UI.iPhone.createGroupedView = function(a,b,c) { return Ti.UI.createGroupedView(a,b,c); };"];
	[js appendString:@"function alert(msg) { Ti.UI.createAlertDialog({title:'Alert',message:msg}).show(); };"];
	
	[self evalJS:js];
}

-(void)shutdown
{
#if KROLLBRIDGE_MEMORY_DEBUG==1
	NSLog(@"DESTROY: %@",self);
#endif
	// fire a notification event to our listeners
	NSNotification *notification = [NSNotification notificationWithName:kKrollShutdownNotification object:self];
	[[NSNotificationCenter defaultCenter] postNotification:notification];

	[context stop];
}

-(void)gc
{
	[context gc];
	[titanium gc];
}

#pragma mark Delegate

-(void)willStartNewContext:(KrollContext*)kroll
{
}

-(void)didStartNewContext:(KrollContext*)kroll
{
	// create Titanium global object
	titanium = [[TitaniumObject alloc] initWithContext:kroll host:host];
	TiContextRef jsContext = [kroll context];
	TiValueRef tiRef = [KrollObject toValue:kroll value:titanium];

	TiStringRef prop = TiStringCreateWithUTF8CString("Titanium");
	TiStringRef prop2 = TiStringCreateWithUTF8CString("Ti");
	TiObjectRef globalRef = TiContextGetGlobalObject(jsContext);
	TiObjectSetProperty(jsContext, globalRef, prop, tiRef, NULL, NULL);
	TiObjectSetProperty(jsContext, globalRef, prop2, tiRef, NULL, NULL);
	TiStringRelease(prop);
	TiStringRelease(prop2);	
	
	[host registerContext:self forToken:[kroll contextId]];
	
	//if we have a preload dictionary, register those static key/values into our UI namespace
	//in the future we may support another top-level module but for now UI is only needed
	if (preload!=nil)
	{
		KrollObject *ti = (KrollObject*)[titanium valueForKey:@"UI"];
		for (id key in preload)
		{
			id target = [preload objectForKey:key];
			KrollObject *ko = [[KrollObject alloc] initWithTarget:target context:context];
			[ti setStaticValue:ko forKey:key];
			[ko release];
		}
		[self injectPatches];
		[self evalFile:[url path] callback:self selector:@selector(booted)];	
	}
	else 
	{
		// now load the app.js file and get started
		NSURL *startURL = [host startURL];
		[self injectPatches];
		[self evalFile:[startURL absoluteString] callback:self selector:@selector(booted)];
	}
}

-(void)willStopNewContext:(KrollContext*)kroll
{
	[titanium gc];
	[host unregisterContext:self forToken:[kroll contextId]];
}

-(void)didStopNewContext:(KrollContext*)kroll
{
	RELEASE_TO_NIL(titanium);
	RELEASE_TO_NIL(context);
	RELEASE_TO_NIL(preload);
}

@end