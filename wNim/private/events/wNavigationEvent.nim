#====================================================================
#
#               wNim - Nim's Windows GUI Framework
#                 (c) Copyright 2017-2020 Ward
#
#====================================================================

## This event is generated by wControl when it need to know a navigation key
## is used by the control or not.
#
## :Superclass:
##   `wEvent <wEvent.html>`_
#
## :Seealso:
##   `wControl <wControl.html>`_
#
## :Events:
##   ==============================  =============================================================
##   wNavigationEvent                Description
##   ==============================  =============================================================
##   wEvent_Navigation               A navigation key was pressed.
##   ==============================  =============================================================

{.experimental, deadCodeElim: on.}
when defined(gcDestructors): {.push sinkInference: off.}

import ../wBase

wEventRegister(wNavigationEvent):
  wEvent_Navigation

method getKeyCode*(self: wNavigationEvent): int {.property, inline.} =
  ## Returns the key code of the key that generated this event.
  result = int self.mWparam