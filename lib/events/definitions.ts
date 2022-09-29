/**
 * Define events, callbacks etc
 */

import {FileTransferEventType, WatchPayload} from '../native-module';
import {FileTransfer} from '../files';

export interface FileTransferEvent extends FileTransfer {
  type: FileTransferEventType;
}

export type WatchMessageCallback<
  MessageFromWatch = WatchPayload,
  MessageToWatch = WatchPayload
> = (
  payload: MessageFromWatch & {id?: string},
  // if the watch sends a message without a messageId, we have no way to respond
  replyHandler: ((resp: MessageToWatch) => void) | null,
) => void;

export interface WatchEventCallbacks<
  P extends WatchPayload = WatchPayload,
  P2 extends WatchPayload = WatchPayload
> {
  'activation-error': (payload: P) => void;
  'application-context': (payload: P) => void;
  'application-context-error': (payload: P) => void;
  'application-context-received-error': (payload: P) => void;
  file: (event: FileTransferEvent) => void;
  'file-received': (payload: P[]) => void;
  'file-received-error': (payload: P[]) => void;
  installed: (installed: boolean) => void;
  message: WatchMessageCallback<P, P2>;
  paired: (paired: boolean) => void;
  reachability: (reachable: boolean) => void;
  'session-became-inactive': (payload: P) => void;
  'session-did-deactivate': (payload: P) => void;
  'user-info': (payload: P[]) => void;
  'user-info-error': (payload: P) => void;
}

export type WatchEvent = keyof WatchEventCallbacks;
