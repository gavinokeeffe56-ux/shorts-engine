import React from 'react';
import {Composition} from 'remotion';
import {Short, Timeline} from './Short';

export const Root: React.FC = () => (
  <Composition
    id="Short"
    component={Short as any}
    width={1080}
    height={1920}
    fps={30}
    durationInFrames={300}
    defaultProps={{timeline: null as unknown as Timeline}}
    calculateMetadata={({props}) => ({
      durationInFrames: Math.ceil((props as any).timeline.duration * 30),
    })}
  />
);
