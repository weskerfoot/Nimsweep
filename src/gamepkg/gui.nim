import algorithm, heapqueue, random, options, sequtils, sugar, tables
import raylib, raygui

from times import getTime, toUnix, nanosecond

# Seed rng
let now = getTime()
randomize(now.toUnix * 1_000_000_000 + now.nanosecond)

# constants
const rowSize = 20 # How many tiles per row of the board
const boardOffset: int = 50 # How far is the board from the top of the window
const boxStride: int = 40 # How much space does a tile take up
const borderWidth: float32 = 6.float32 # How wide are the borders between tiles
const sideSize = (boxStride-borderWidth.int).float32 # How long is a side of a tile
const boardLength = (boxStride+borderWidth.int) * rowSize # How long is a side of the board
const infinity = (1.0/0.0).float32
const averageMineCount = ((rowSize*rowSize) * 0.10).int # How many mines should be placed on average?

type GameState = enum
  unfinished,
  lost,
  won

type TileState = object
  mine: bool # is it a mine?
  marked: bool # have we marked it as a mine?
  revealed: bool # has it been revealed?, implies the search algorithm ran
  mineNeighbours: int

type Tile = ref object of RootObj
  state: TileState
  pos: Rectangle
  x: int
  y: int

proc `$` (t: Tile): string =
  return "state = " & $t.state & ", " & "x = " & $t.x & ", " & "y = " & $t.y

type Board = ref object of RootObj
  tiles: seq[Tile]
  xIntervals: seq[tuple[l: float32, h: float32]]
  yIntervals: seq[tuple[l: float32, h: float32]]

proc isWinning(board: Board): bool =
  # If All tiles are either revealed or mines (but not both), you won
  board.tiles.all((tile) => (tile.state.mine and (not tile.state.revealed)) or tile.state.revealed)

proc getTile(board: Board, x: int, y: int): Option[Tile] =
  # Given x, y coords, get tile if it exists
  if x > (rowSize - 1) or y > (rowSize - 1) or x < 0 or y < 0:
    return none(Tile)

  let l = board.tiles.len 
  let pos = (rowSize * y) + x

  if pos >= 0 and pos < l:
    return some(board.tiles[pos])

  none(Tile)

proc getNeighbours(board: Board, tile: Tile): seq[Tile] =
  let x = tile.x
  let y = tile.y

  let positions = @[
           @[x+1, y],
           @[x+1, y+1],
           @[x+1, y-1],
           @[x, y+1],
           @[x, y-1],
           @[x-1, y+1],
           @[x-1, y],
           @[x-1, y-1]
  ] # neighboring coordinates to check

  let filteredPositions = filterIt(positions, getTile(board, it[0], it[1]).isSome)

  assert(filteredPositions.len >= 3 and filteredPositions.len <= 8)

  return map(filteredPositions, (pos) => getTile(board, pos[0], pos[1]).get)

proc revealBoard(board: Board, tile: Tile) =
  # Recursively reveal neighbours unless one of them is a mine
  var q = initHeapQueue[Tile]()
  q.push(tile)

  var processed = initTable[string, bool]()

  while q.len > 0:
    var skip: bool = false
    let t = q.pop()
    let k = $t.x & "," & $t.y

    if processed.contains(k):
      continue

    processed[k] = true

    # If it's not a mine, reveal it
    t.state.revealed = true

    # If any of the neighbours are mines, stop
    let neighbours = getNeighbours(board, t)

    if anyIt(neighbours, it.state.mine):
      t.state.mineNeighbours = filterIt(neighbours, it.state.mine).len
      continue

    # Add all the neighbours to the queue to be processed
    for neighbour in neighbours:
        if processed.contains(($neighbour.x & "," & $neighbour.y)):
          continue

        # Must not add mines to the queue
        assert(not neighbour.state.mine)
        q.push(neighbour)

proc setMine(numMines: int): bool =
  let maxR: float = rowSize*rowSize
  return rand(max_r) < (numMines.float)

proc comparator(a: tuple[l: float32, h: float32], k: int): int =
  if k.float32 < a.l:
    return 1
  if k.float32 > a.h:
    return -1
  else:
    return 0

proc getTilePos(mouseX: int, mouseY: int, board: Board): int =
  # Take x, y coordinates of cursor
  # Do search for the tile x and y coordinates using intervals
  # Return position in the set of tiles

  if mouseX.float32 > boardLength or mouseY.float32 > boardLength:
    return -1

  let x: int = board.xIntervals.binarySearch(mouseX, comparator) - 1
  let y: int = board.yIntervals.binarySearch(mouseY, comparator) - 1
  return (y*rowSize) + x

proc drawTile(heightPos: int, widthPos: int, state: TileState, reveal: bool = false): Tile =
  let edge = 1.float32
  let y = boardOffset+(boxStride*heightPos)
  let x = boardOffset+(boxStride*widthPos)

  let boxRect = Rectangle(x: x.float32, y: y.float32, width: sideSize, height: sideSize)

  let c1 = Color(r: 2, g: 91, b: 36, a: 255)
  let c2 = Color(r: 0, g: 0, b: 0, a: 255)
  let c3 = Color(r: 0, g: 91, b: 109, a: 255)
  let c4 = Color(r: 0, g: 212, b: 255, a: 255)

  if state.mine and reveal:
    DrawRectangleRec(boxRect, RED)
  elif state.revealed:
    DrawRectangleRec(boxRect, GREEN)
    if state.mineNeighbours > 0:
      DrawText($state.mineNeighbours, x+(sideSize/4).int, y, sideSize.int, BLACK)

  # show everything if `reveal` is true
  elif reveal:
    DrawRectangleRec(boxRect, GREEN)
  else:
    DrawRectangleGradientEx(boxRect, c1, c2, c3, c4)

  let start1 = Vector2(x: x.float32+edge, y: y.float32+edge)
  let end1 = Vector2(x: (x+boxStride).float32-borderWidth-edge, y: (y+boxStride).float32-borderWidth-edge)

  let start2 = Vector2(x: (x).float32+edge,
                       y: (y+boxStride).float32-borderWidth-edge)

  let end2 = Vector2(x: (x+boxStride).float32-borderWidth-edge,
                     y: y.float32+edge)

  if state.marked:
    DrawLineEx(start1, end1, 3, WHITE)
    DrawLineEx(start2, end2, 3, WHITE)

  return Tile(state: state, x: widthPos, y: heightPos, pos: boxRect)

proc drawBoardWindow() =
  DrawRectangle(boardOffset, boardOffset, boardLength, boardLength, BLACK)

proc generateBoard(screenWidth: int, screenHeight: int, rowSize: int): Board =
  # Draw the initial board
 
  drawBoardWindow()
  var tiles: seq[Tile]
  var xIntervals: seq[tuple[l: float32, h: float32]] = @[]
  var yIntervals: seq[tuple[l: float32, h: float32]] = @[]

  for heightPos in countup(0, rowSize-1, 1):
    xIntervals = @[]
    for widthPos in countup(0, rowSize-1, 1):
      var state: TileState

      state.marked = false
      state.revealed = false
      state.mine = setMine(averageMineCount) # average number of mines
      state.mineNeighbours = 0

      let tile = drawTile(heightPos, widthPos, state)

      tiles &= @[tile]

      # FIXME ugly shit, encapsulate it into a function or make it more terse
      if xIntervals.len > 0:
        xIntervals &= @[(l: xIntervals[xIntervals.high].h, h: tile.pos.x.float32)]
      else:
        xIntervals &= @[(l: 0.float32, h: tile.pos.x.float32)]

    if yIntervals.len > 0:
      yIntervals &= @[(l: yIntervals[yIntervals.high].h, h: tiles[tiles.high].pos.y.float32)]
    else:
      yIntervals &= @[(l: 0.float32, h: tiles[tiles.high].pos.y.float32)]

  # Required for fencepost cases
  xIntervals &= (l: xIntervals[xIntervals.high].h, h: infinity)
  yIntervals &= (l: yIntervals[yIntervals.high].h, h: infinity)

  result = Board(tiles: tiles, xIntervals: xIntervals, yIntervals: yIntervals)

proc drawBoard(screenWidth: int, screenHeight: int, board: Board) =
  drawBoardWindow()
  for tile in board.tiles:
    discard drawTile(tile.y, tile.x, tile.state)

proc showBoard(screenWidth: int, screenHeight: int, board: Board) =
  # Show the entire board
  drawBoardWindow()
  for tile in board.tiles:
    discard drawTile(tile.y, tile.x, tile.state, reveal=true)

proc guiLoop*() =

  echo "gui loop starting"

  # TODO get from xlib
  var screenWidth: int = 100
  var screenHeight: int = 100

  SetConfigFlags(ord(ConfigFlags.FLAG_WINDOW_UNDECORATED))

  InitWindow(screenWidth, screenHeight, "Minesweeper")

  let monitor = GetCurrentMonitor()
  screenWidth = (monitor.GetMonitorWidth() / 2).int
  screenHeight = (monitor.GetMonitorHeight() / 2).int

  SetWindowSize(screenWidth, screenHeight)
  SetWindowTitle("Minesweeper")
  MaximizeWindow()

  GuiLoadStyle("styles/terminal/terminal.rgs")
  #echo GetScreenWidth()
  #echo GetScreenHeight()

  var mousePos = Vector2(x: 0, y: 0)
  var windowPos = Vector2(x: screenWidth.float32, y: screenHeight.float32)
  var panOffset = mousePos

  var dragWindow = false
  var exitWindow = false

  var board: Option[Board] = none(Board)
  var gameState: GameState = unfinished

  SetTargetFPS(60)

  while not exitWindow and not WindowShouldClose():
    screenWidth = (monitor.GetMonitorWidth()).int
    screenHeight = (monitor.GetMonitorHeight()).int
    mousePos = GetMousePosition()

    if IsMouseButtonPressed(MOUSE_LEFT_BUTTON):
      if CheckCollisionPointRec(mousePos, Rectangle(x: 0.float32, y: 0.float32, width: screenWidth.float32, height: 20.float32)):
        dragWindow = true
        panOffset = mousePos

      else:
        # Check if we're clicking a minefield tile
        if board.isSome and gameState == unfinished:
          echo isWinning(board.get)
          let tilePos = getTilePos(mousePos.x.int, mousePos.y.int, board.get) # TODO make this take vector2 instead ?
          if tilePos >= 0:
            let tile = board.get.tiles[tilePos]
            if tile.state.mine and not tile.state.marked:
              echo "boom!"
              gameState = lost
            if tile.state.marked:
              echo "do nothing"
            else:
              echo "reveal it"
              revealBoard(board.get, tile)

      if isWinning(board.get):
        echo "You won!"
        gameState = won

    if IsMouseButtonPressed(MOUSE_RIGHT_BUTTON):
      if board.isSome:
        let tilePos = getTilePos(mousePos.x.int, mousePos.y.int, board.get)
        if tilePos >= 0:
          let tile = board.get.tiles[tilePos]
          if not tile.state.revealed:
            board.get.tiles[tilePos].state.marked = not tile.state.marked

    if dragWindow:
      windowPos.x += (mousePos.x - panOffset.x)
      windowPos.y += (mousePos.y - panOffset.y)

      if IsMouseButtonReleased(MOUSE_LEFT_BUTTON):
        dragWindow = false

      SetWindowPosition(windowPos.x.int, windowPos.y.int)

    BeginDrawing()

    # This must come before anything else!
    ClearBackground(RAYWHITE)

    exitWindow = GuiWindowBox(Rectangle(x: 0.float32, y: 0.float32, width: screenWidth.float32, height: screenHeight.float32),
                              "#198# Minesweeper".cstring)

    if board.isNone:
      # Generate the initial board if there isn't one
      board = some(generateBoard(screenWidth, screenHeight, rowSize))
    else:
      if gameState == won and board.isSome:
        showBoard(screenWidth, screenHeight, board.get)
        DrawText("You won!", (screenWidth/2).int, (screenHeight/2).int, 30, GREEN)

      elif gameState == lost and board.isSome:
        showBoard(screenWidth, screenHeight, board.get)
        DrawText("You lost! :(", (screenWidth/2).int, (screenHeight/2).int, 30, RED)

      # Otherwise update the state of the abstract board with the window
      else:
        drawBoard(screenWidth, screenHeight, board.get)

    EndDrawing()

  CloseWindow()
