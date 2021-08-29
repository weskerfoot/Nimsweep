import algorithm, heapqueue, random, options, sequtils, sugar, tables
import raylib, raygui

from times import getTime, toUnix, nanosecond

# Seed rng
let now = getTime()
randomize(now.toUnix * 1_000_000_000 + now.nanosecond)

type GameConfig = object
  rowSize: int
  boxStride: int
  borderWidth: float32
  sideSize: float32
  boardOffset: int
  averageMineCount: int

proc makeConfig(rowSize: int,
                borderWidth: float32,
                boardOffset: int,
                minePercentage: float32 = 0.10) : GameConfig =
  let boxStride: int = (950 * (1/rowSize)).int # How much space does a tile take up
  let sideSize = (boxStride-borderWidth.int).float32 # How long is a side of a tile
  let averageMineCount = ((rowSize*rowSize).float32 * minePercentage) # How many mines should be placed on average?

  GameConfig(rowSize: rowSize,
             boxStride: boxStride,
             borderWidth: borderWidth,
             sideSize: sideSize,
             boardOffset: boardOffset,
             averageMineCount: averageMineCount.int)

const gameConf = makeConfig(20, 6, 70)

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
  if x > (gameConf.rowSize - 1) or y > (gameConf.rowSize - 1) or x < 0 or y < 0:
    return none(Tile)

  let l = board.tiles.len 
  let pos = (gameConf.rowSize * y) + x

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
  let maxR: float = gameConf.rowSize*gameConf.rowSize
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
  
  assert(board.xIntervals.len > 0)
  assert(board.yIntervals.len > 0)

  if mouseX.float32 > board.xIntervals[^1].h or mouseY.float32 > board.yIntervals[^1].h:
    return -1

  if mouseX < gameConf.boardOffset or mouseY < gameConf.boardOffset:
    return -1

  let x: int = board.xIntervals.binarySearch(mouseX, comparator) - 1
  let y: int = board.yIntervals.binarySearch(mouseY, comparator) - 1

  return (y*gameConf.rowSize) + x

proc drawTile(heightPos: int, widthPos: int, state: TileState, reveal: bool = false): Tile =
  let edge = 1.float32 # How far from the edge is the X
  let y = gameConf.boardOffset+(gameConf.boxStride*heightPos)
  let x = gameConf.boardOffset+(gameConf.boxStride*widthPos)

  let boxRect = Rectangle(x: x.float32, y: y.float32, width: gameConf.sideSize, height: gameConf.sideSize)

  let c1 = Color(r: 2, g: 91, b: 36, a: 255)
  let c2 = Color(r: 0, g: 0, b: 0, a: 255)
  let c3 = Color(r: 0, g: 91, b: 109, a: 255)
  let c4 = Color(r: 0, g: 212, b: 255, a: 255)

  if state.mine and reveal:
    DrawRectangleRec(boxRect, RED)
  elif state.revealed:
    DrawRectangleRec(boxRect, GREEN)
    if state.mineNeighbours > 0:
      DrawText($state.mineNeighbours, x+(gameConf.sideSize/4).int, y, gameConf.sideSize.int, BLACK)

  # show everything if `reveal` is true
  elif reveal:
    DrawRectangleRec(boxRect, GREEN)
  else:
    DrawRectangleGradientEx(boxRect, c1, c2, c3, c4)

  let start1 = Vector2(x: x.float32+edge, y: y.float32+edge)
  let end1 = Vector2(x: (x+gameConf.boxStride).float32-gameConf.borderWidth-edge, y: (y+gameConf.boxStride).float32-gameConf.borderWidth-edge)

  let start2 = Vector2(x: (x).float32+edge,
                       y: (y+gameConf.boxStride).float32-gameConf.borderWidth-edge)

  let end2 = Vector2(x: (x+gameConf.boxStride).float32-gameConf.borderWidth-edge,
                     y: y.float32+edge)

  if state.marked:
    DrawLineEx(start1, end1, 3, WHITE)
    DrawLineEx(start2, end2, 3, WHITE)

  return Tile(state: state, x: widthPos, y: heightPos, pos: boxRect)

proc drawBoardWindow() =
  DrawRectangle(gameConf.boardOffset, gameConf.boardOffset, gameConf.boxStride*gameConf.rowSize, gameConf.boxStride*gameConf.rowSize, BLACK)

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
      state.mine = setMine(gameConf.averageMineCount) # average number of mines
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
  let lastXInterval = xIntervals[xIntervals.high]
  let lastYInterval = xIntervals[xIntervals.high]
  xIntervals &= (l: lastXInterval.h, h: lastXInterval.h + tiles[0].pos.width)
  yIntervals &= (l: lastYInterval.h, h: lastYInterval.h + tiles[0].pos.height)

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

  var mousePos = Vector2(x: 0, y: 0)
  var windowPos = Vector2(x: screenWidth.float32, y: screenHeight.float32)
  var panOffset = mousePos

  var dragWindow = false
  var exitWindow = false

  var restartButton = false

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
          let tilePos = getTilePos(mousePos.x.int, mousePos.y.int, board.get) # TODO make this take vector2 instead ?
          if tilePos >= 0:
            let tile = board.get.tiles[tilePos]
            if tile.state.mine and not tile.state.marked:
              gameState = lost
            if not tile.state.marked:
              revealBoard(board.get, tile)

      if isWinning(board.get) and gameState != lost:
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

    restartButton = GuiButton(Rectangle(x: gameConf.boardOffset.float32-10, y: gameConf.boardOffset.float32-20, width: 80.float32, height: 20.float32), "Restart")

    if board.isNone or restartButton:
      # Generate the initial board if there isn't one
      board = some(generateBoard(screenWidth, screenHeight, gameConf.rowSize))
      gameState = unfinished
    else:
      if gameState == won and board.isSome:
        showBoard(screenWidth, screenHeight, board.get)
        DrawText("You won! :)", (screenWidth.float32/2.5).int, (gameConf.boardOffset/2).int, 30, GREEN)

      elif gameState == lost and board.isSome:
        showBoard(screenWidth, screenHeight, board.get)
        DrawText("You lost! :(", (screenWidth.float32/2.5).int, (gameConf.boardOffset/2).int, 30, RED)

      # Otherwise update the state of the abstract board with the window
      else:
        drawBoard(screenWidth, screenHeight, board.get)

    EndDrawing()
  CloseWindow()
