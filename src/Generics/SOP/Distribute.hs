{-# LANGUAGE ConstraintKinds       #-}
{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE GADTs                 #-}
{-# LANGUAGE KindSignatures        #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PolyKinds             #-}
{-# LANGUAGE RankNTypes            #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TypeOperators         #-}
module Generics.SOP.Distribute
  (
    expand
  , expandA
  , WrappedProjection
  , wrappedProjections
  , shiftWrappedProjection
  , WrappedInjection
  , wrappedInjections
  , shiftWrappedInjection
  , distributeNP
  , distributeI_NP
  , functorToNP
  , reAssociateNP
  , distributeToFields
  , reconstructA
  , functionPOPFromClass
  , Dict
  ) where

import           Generics.SOP      hiding (Compose)
import           Generics.SOP.Dict (Dict, withDict)

expand::forall (f :: [k] -> *) xs.(SListI xs)=>NS f xs -> NP (Maybe :.: f) xs
expand ns = go sList (Just ns) where
  go::forall ys.SListI ys => SList ys -> Maybe (NS f ys) -> NP (Maybe :.: f) ys
  go SNil _ = Nil
  go SCons mNS = case mNS of
    Nothing -> Comp Nothing :* go sList Nothing -- after Z
    Just ms -> case ms of
      Z fx  -> Comp (Just fx) :* go sList Nothing -- at Z
      S ms' -> Comp Nothing :* go sList (Just ms') -- before Z


expandA::Generic a=>a->NP (Maybe :.: NP I) (Code a)
expandA = expand . unSOP . from

type WrappedProjection (g :: * -> *) (f :: k -> *) (xs :: [k]) = K (g (NP f xs)) -.-> g :.: f

wrappedProjections::forall xs g f.(Functor g,SListI xs) => NP (WrappedProjection g f xs) xs
wrappedProjections = case sList :: SList xs of
  SNil -> Nil
  SCons -> fn (Comp . fmap hd . unK) :* hliftA shiftWrappedProjection wrappedProjections

shiftWrappedProjection :: Functor g=>WrappedProjection g f xs a -> WrappedProjection g f (x ': xs) a
shiftWrappedProjection (Fn f) = Fn $ f . K . fmap tl . unK

type WrappedInjection (g :: * -> *) (f :: k -> *) (xs :: [k]) = g :.: f -.-> K (g (NS f xs))

wrappedInjections::forall xs g f. (Functor g, SListI xs) => NP (WrappedInjection g f xs) xs
wrappedInjections = case sList :: SList xs of
  SNil   -> Nil
  SCons  -> fn (K . fmap Z . unComp) :* hliftA shiftWrappedInjection wrappedInjections

shiftWrappedInjection:: Functor g=>WrappedInjection g f xs a -> WrappedInjection g f (x ': xs) a
shiftWrappedInjection (Fn f) = Fn $ K . fmap S . unK . f

-- NB: For applicative h, this is an inverse of hsequence.  If h is not applicative, then this is not invertible.
distributeNP::(Functor h, SListI xs)=>h (NP g xs) -> NP (h :.: g) xs
distributeNP x = hap wrappedProjections (hpure $ K x)

distributeI_NP::(Functor h, SListI xs)=>h (NP I xs) -> NP h xs
distributeI_NP = hmap (fmap unI . unComp) . distributeNP

functorToNP::forall g a.(Functor g,Generic a)=>g a -> NP (g :.: (Maybe :.: NP I)) (Code a)
functorToNP ga = hap wrappedProjections (hpure $ K (expandA <$> ga))

reAssociate::Functor g=>(g :.: (f :.: h)) a -> ((g :.: f) :.: h) a
reAssociate = Comp . Comp . fmap unComp . unComp

reAssociateNP::(Functor g, SListI xss)=>NP (g :.: (f :.: h)) xss->NP ((g :.: f) :.: h) xss
reAssociateNP = hmap reAssociate

distributeToFields::(Functor g, SListI2 xss)=>NP ((g :.: Maybe) :.: NP I) xss -> POP (g :.: Maybe) xss
distributeToFields =
  let proxyC = Proxy :: Proxy SListI
  in POP . hcliftA proxyC (distributeI_NP . unComp)

reconstructA::(Functor h, Generic a) => NP (h :.: NP I) (Code a) -> NP (K (h a)) (Code a)
reconstructA = hliftA (K . fmap (to . SOP) . unK) . hap wrappedInjections

functionPOPFromClass::forall c f g xss.SListI2 xss=>Dict (All2 c) xss->(forall a.c a=>f a -> g a)->POP (f -.-> g) xss
functionPOPFromClass d fn = withDict d $ hcpure (Proxy :: Proxy c) $ Fn fn

{-
functionPOPFromClass'::forall c f g xss.(All2 c xss, SListI2 xss)=>(forall a.c a=>f a -> g a)->POP (f -.-> g) xss
functionPOPFromClass' fn =
  let dict :: Dict (All2 c) xss
      dict = all_POP hdicts
  in  withDict dict $ hcpure (Proxy :: Proxy c) $ Fn fn
-}


