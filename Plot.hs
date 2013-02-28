{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE ExistentialQuantification #-}
{- | Example implementation for displaying signals

-}
module Plot(
      StyledSignal
    , SignalStyle(..) 
    , PlotStyle(..)
    , AnySignal(..)
    , defaultPlotStyle
    , defaultSignalStyle
    , discreteSignalsWithStyle
    , signalsWithStyle
    , display
    , drawStringLabel
    , LabelStyle(..)
    ) where 

import Graphics.PDF
import Displayable 
import Viewer
import Text.Printf
import qualified Graphics.PDF as PDF(Orientation(..))
import Control.Monad(when) 
import Data.Maybe(isJust,fromJust)
import Signal
import Fixed(HasDoubleRepresentation(..))

import Debug.Trace
debug a = trace (show a) a


-- | A list fo signals wth style information for the plot and the signals
-- The signals are using the same units
data StyledSignal a b = StyledSignal [[(a,b)]] (PlotStyle a b)

-- | Style for a signal (only color used in this version)
data SignalStyle = SignalStyle {
                  signalColor :: Color 
                , signalWidth :: Double
                , signalOpacity :: Double
}

-- | Style for a label
data LabelStyle = LabelStyle Int Justification PDF.Orientation 


{-

Default styles

-}
hUnitStyle = LabelStyle 7 LeftJustification PDF.E
vUnitStyle = LabelStyle 7 Centered PDF.S

hTickStyle = LabelStyle 7 Centered PDF.N
vTickStyle = LabelStyle 7 RightJustification PDF.W

titleStyle = LabelStyle 14 Centered PDF.N

-- | Draw a string value with style and wrapping
drawStringLabel :: LabelStyle 
                -> String 
                -> PDFFloat 
                -> PDFFloat 
                -> PDFFloat 
                -> PDFFloat 
                -> Draw () 
drawStringLabel (LabelStyle fs j o) s x y w h = do
  let (r,b) = drawTextBox x y w h o NormalParagraph (Font (PDFFont Times_Roman fs) black black) $ do
                setJustification j
                paragraph $ do
                    txt $ s
  b

-- | Default style for a signal
defaultSignalStyle :: Double -> Color -> SignalStyle 
defaultSignalStyle opacity color = SignalStyle color 1.0 opacity

-- | Style for a plot
data PlotStyle a b = PlotStyle {
                       title :: Maybe String 
                     , leftMargin :: Double 
                     , rightMargin :: Double 
                     , topMargin :: Double 
                     , bottomMargin :: Double 
                     , horizontalTickValues :: Double -> Double -> [Double]
                     , verticalTickValues :: Double -> Double -> [Double] 
                     , horizontalTickRepresentation :: Double -> String
                     , verticalTickRepresentation :: Double -> String
                     , horizontalLabel :: Maybe String 
                     , verticalLabel:: Maybe String
                     , prolog :: ((a,b) -> Point) -> Draw ()
                     , epilog :: ((a,b) -> Point) -> Draw () 
                     , signalStyles :: [SignalStyle]
                     , axis :: Bool
                     , interpolation :: Bool
                     , defaultWidth :: Double 
                     , defaultHeight :: Double
                     , horizontalBounds :: Maybe (Double,Double)
                     , verticalBounds :: Maybe (Double,Double)
}

-- | Default ticks values in [ma,mb]
tenTicks :: Double -> Double -> [Double]
tenTicks ma mb = map (\t -> (fromIntegral t)/(fromIntegral 10)*(mb-ma) + ma) ([0..10] :: [Int])

-- | Formatting function for floats
simpleFloat :: HasDoubleRepresentation a => a -> String
simpleFloat a = 
    let s = printf "%1.2f" (toDouble a) 
    in 
    s

-- | Default style for plots
defaultPlotStyle :: PlotStyle a b 
defaultPlotStyle = PlotStyle {
                  title = Nothing 
                , leftMargin = 50 
                , rightMargin = 50 
                , topMargin = 50 
                , bottomMargin = 20 
                , defaultWidth = 600.0 
                , defaultHeight = 400.0
                , horizontalTickValues = tenTicks 
                , verticalTickValues = tenTicks 
                , horizontalTickRepresentation = simpleFloat
                , verticalTickRepresentation = simpleFloat
                , horizontalLabel = Just "s"
                , verticalLabel = Just "Energy"
                , prolog = const (return ()) 
                , epilog = const (return ()) 
                , signalStyles = repeat (defaultSignalStyle 1.0 (Rgb 0.6 0.6 1.0))
                , axis = True
                , interpolation = True
                , horizontalBounds = Nothing 
                , verticalBounds = Nothing
}

-- | Create a plot description with signals and a plot style
signalsWithStyle :: [[(a,b)]] -> PlotStyle a b -> StyledSignal a b 
signalsWithStyle signals style = StyledSignal signals style

data AnySignal = forall b. HasDoubleRepresentation b => AS (Signal b) 

-- | Create a plot description with discrete signals and a plot style
discreteSignalsWithStyle :: HasDoubleRepresentation t 
                         => [t]
                         -> PlotStyle Double Double 
                         -> [AnySignal] 
                         -> StyledSignal Double Double 
discreteSignalsWithStyle theTimes' style signals  = 
    let theTimes = map toDouble theTimes'
        convertSignal (AS s) = map toDouble . toListS $ s
        timedSignal s = zip theTimes (convertSignal s)
        theCurves = map timedSignal signals
    in 
    signalsWithStyle theCurves style

-- | A plot description is Displayable
instance (Ord a, Ord b, HasDoubleRepresentation a, HasDoubleRepresentation b) =>  Displayable (StyledSignal a b) where 
    drawing (StyledSignal signals s) = do 
        let width = defaultWidth s
            height = defaultHeight s
            tickSize = 6
            tickLabelSep = 5
            hUnitSep = 5
            vUnitSep = 15
            titleSep = 5
            (ta,tb) = maybe ( minimum . map (minimum . map (toDouble . fst)) $ signals 
                            , maximum . map (maximum . map (toDouble . fst)) $ signals) id (horizontalBounds s)
            (ya,yb) = maybe ( minimum . map (minimum . map (toDouble . snd)) $ signals 
                            , maximum . map (maximum . map (toDouble . snd))$ signals) id (verticalBounds s) 
            h a = (toDouble a - ta) / (tb - ta)*(width - leftMargin s - rightMargin s) + leftMargin s 
            v b = (toDouble b - ya) / (yb - ya)*(height - topMargin s - bottomMargin s) + bottomMargin s
            pt (a,b) = (h a) :+ (v b)
            segmentedDraw h (n:l) = do 
                let (ha :+ hb) = pt h 
                    (na :+ nb) = pt n 
                addLineToPath (na :+ hb) 
                addLineToPath (na :+ nb) 
                segmentedDraw n l
            segmentedDraw h [] = return ()
            drawVTick x y = do 
                let (a :+ b) = pt (x,y) 
                stroke $ Line (a - tickSize) b a b
                drawStringLabel vTickStyle ((verticalTickRepresentation s) y) 
                     (a - tickSize - tickLabelSep) b (leftMargin s) (bottomMargin s) 
            drawHTick y x = do 
                let (a :+ b) = pt (x,y) 
                stroke $ Line a b a (b - tickSize)
                drawStringLabel hTickStyle ((horizontalTickRepresentation s) x) 
                    a (b - tickSize - tickLabelSep) (leftMargin s) (bottomMargin s) 
            getPath l = do 
                beginPath (pt . head $ l) 
                if (interpolation s)
                    then do              
                        mapM_ (addLineToPath . pt) (tail l)
                    else do 
                        segmentedDraw (head l) (tail l)
            drawSignal (l,signalstyle) = do 
                getPath l
                strokeColor (signalColor signalstyle)
                setStrokeAlpha (signalOpacity signalstyle)
                strokePath
                setStrokeAlpha 1.0
            drawYAxis x = do 
                strokeColor black 
                let (sa :+ sb) = pt (x,ya)  
                    (_ :+ eb) = pt (x,yb)
                stroke $ Line sa sb sa eb
                mapM_ (drawVTick x) (filter (\y -> y >= ya && y <= yb) $ (verticalTickValues s) ya yb)
            drawXAxis y = do 
                strokeColor black 
                let (sa :+ sb) = pt (ta,y) 
                    (ea :+ _) = pt (tb,y) 
                stroke $ Line sa sb ea sb
                mapM_ (drawHTick y) (filter (\t -> t >= ta && t <= tb) $ (horizontalTickValues s) ta tb)
            drawHLabel _ Nothing = return () 
            drawHLabel y (Just label) = do 
                    let b = v y
                    drawStringLabel hUnitStyle label (width - rightMargin s + hUnitSep) b  (rightMargin s - hUnitSep) (bottomMargin s) 
            drawYLabel _ Nothing = return () 
            drawYLabel x (Just label) = do
                    let a = h x 
                    drawStringLabel vUnitStyle label a (height - topMargin s + vUnitSep) (leftMargin s) (topMargin s - vUnitSep)
        withNewContext $ do
            addShape $ Rectangle (leftMargin s :+ bottomMargin s) ((width - rightMargin s) :+ (height - topMargin s))
            setAsClipPath
            (prolog s) pt
            mapM_ drawSignal (zip signals (cycle $ signalStyles s))
        if (axis s) 
            then do 
                let xaxis = if ta <=0 && tb >=0 then 0 else ta 
                    yaxis = if ya <=0 && yb >=0 then 0 else ya 
                drawXAxis yaxis 
                drawYAxis xaxis 
                drawHLabel yaxis (horizontalLabel s)
                drawYLabel xaxis (verticalLabel s)
            else do
                let xaxis = ta 
                    yaxis = ya
                drawXAxis yaxis 
                drawYAxis xaxis
                drawHLabel yaxis (horizontalLabel s)
                drawYLabel xaxis (verticalLabel s)
        when (isJust (title s)) $ do 
            let t = fromJust (title s)
            drawStringLabel titleStyle t (width / 2.0) (height - titleSep) width (topMargin s)
        withNewContext $ do
            addShape $ Rectangle (leftMargin s :+ bottomMargin s) ((width - rightMargin s) :+ (height - topMargin s))
            setAsClipPath
            (epilog s) pt
