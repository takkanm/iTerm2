//
//  Coprocess.m
//  iTerm
//
//  Created by George Nachman on 9/24/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "Coprocess.h"

const int kMaxInputBufferSize = 1024;
const int kMaxOutputBufferSize = 1024;

@implementation Coprocess

@synthesize pid = pid_;
@synthesize outputFd = outputFd_;
@synthesize inputFd = inputFd_;
@synthesize inputBuffer = inputBuffer_;
@synthesize outputBuffer = outputBuffer_;
@synthesize eof = eof_;

+ (Coprocess *)launchedCoprocessWithCommand:(NSString *)command
{
    int inputPipe[2];
    int outputPipe[2];
    pipe(inputPipe);
    pipe(outputPipe);
    pid_t pid = fork();
    if (pid == 0) {
        dup2(inputPipe[0], 0);
        close(inputPipe[0]);
        close(inputPipe[1]);

        dup2(outputPipe[1], 1);
        close(outputPipe[0]);
        close(outputPipe[1]);
        for (int i = 3; i < 256; i++) {
            if (i != outputPipe[1] && i != inputPipe[0]) {
                close(i);
            }
        }

        signal(SIGCHLD, SIG_DFL);
        execl("/bin/sh", "/bin/sh", "-c", [command UTF8String], 0);

        /* exec error */
        fprintf(stderr, "## exec failed %s for command /bin/sh -c %s##\n", strerror(errno), [command UTF8String]);
        _exit(-1);
    } else if (pid < (pid_t)0) {
        [[NSAlert alertWithMessageText:@"Failed to launch coprocess."
                         defaultButton:@"OK"
                       alternateButton:nil
                           otherButton:nil
             informativeTextWithFormat:nil] runModal];
        return nil;
    }

    close(inputPipe[0]);
    close(outputPipe[1]);
    return [Coprocess coprocessWithPid:pid
                              outputFd:inputPipe[1]
                               inputFd:outputPipe[0]];
}

+ (Coprocess *)coprocessWithPid:(pid_t)pid
                       outputFd:(int)outputFd
                        inputFd:(int)inputFd
{
    Coprocess *result = [[[Coprocess alloc] init] autorelease];
    result.pid = pid;
    result.outputFd = outputFd;
    result.inputFd = inputFd;
    return result;
}

- (id)init
{
    self = [super init];
    if (self) {
        inputBuffer_ = [[NSMutableData alloc] init];
        outputBuffer_ = [[NSMutableData alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [inputBuffer_ release];
    [outputBuffer_ release];
    [super dealloc];
}

- (int)write
{
    if (self.pid < 0) {
        return -1;
    }
    int fd = [self writeFileDescriptor];
    int n = write(fd, [outputBuffer_ bytes], [outputBuffer_ length]);

    if (n < 0 && (!(errno == EAGAIN || errno == EINTR))) {
        eof_ = YES;
    } else if (n == 0) {
        eof_ = YES;
    } else if (n > 0) {
        [outputBuffer_ replaceBytesInRange:NSMakeRange(0, n)
                                 withBytes:""
                                    length:0];
    }
    return n;
}

- (int)read
{
    if (self.pid < 0) {
        return -1;
    }
    int rc = 0;
    int fd = [self readFileDescriptor];
    while (inputBuffer_.length < kMaxInputBufferSize) {
        char buffer[1024];
        int n = read(fd, buffer, sizeof(buffer));
        if (n == 0) {
            rc = 0;
            eof_ = YES;
            break;
        } else if (n < 0) {
            if (errno != EAGAIN && errno != EINTR) {
                eof_ = YES;
                rc = n;
                break;
            }
        } else {
            rc += n;
            [inputBuffer_ appendBytes:buffer length:n];
        }
        if (n < sizeof(buffer)) {
            break;
        }
    }
    return rc;
}

- (BOOL)wantToRead
{
    return self.pid >= 0 && !eof_ && (inputBuffer_.length < kMaxInputBufferSize);
}

- (BOOL)wantToWrite
{
    return self.pid >= 0 && !eof_ && (outputBuffer_.length > 0);
}

- (void)mainProcessDidTerminate
{
    [self terminate];
}

- (void)terminate
{
    if (self.pid > 0) {
        kill(self.pid, 15);
        close(self.outputFd);
        close(self.inputFd);
        self.outputFd = -1;
        self.inputFd = -1;
        self.pid = -1;
    }
}

- (int)readFileDescriptor
{
    return self.inputFd;
}

- (int)writeFileDescriptor
{
    return self.outputFd;
}

@end
