loadstring=load
local Vec,QVec={},{}
local function v(x,y,z) return setmetatable({x=x,y=y,z=z},Vec) end
Vec.__add=function(a,b)return v(a.x+b.x,a.y+b.y,a.z+b.z)end
Vec.__sub=function(a,b)return v(a.x-b.x,a.y-b.y,a.z-b.z)end
Vec.__mul=function(a,b) if type(a)=='number' then a,b=b,a end;return v(a.x*b,a.y*b,a.z*b)end
local function q(x,y,z,w) return setmetatable({x=x,y=y,z=z,w=w},QVec)end
QVec.__mul=function(a,b)
    if getmetatable(b)==Vec then
        local t=q(b.x,b.y,b.z,0);local result=a*t*q(-a.x,-a.y,-a.z,a.w);return v(result.x,result.y,result.z)
    end
    return q(a.w*b.x+a.x*b.w+a.y*b.z-a.z*b.y,a.w*b.y-a.x*b.z+a.y*b.w+a.z*b.x,
        a.w*b.z+a.x*b.y-a.y*b.x+a.z*b.w,a.w*b.w-a.x*b.x-a.y*b.y-a.z*b.z)
end
QVec.__index=function(a,k)
    if k=='eulerAngles' then
        local s=math.max(-1,math.min(1,2*(a.w*a.x-a.y*a.z)))
        return v(math.deg(math.asin(s)),math.deg(math.atan(2*(a.w*a.y+a.x*a.z),1-2*(a.x*a.x+a.y*a.y))),
            math.deg(math.atan(2*(a.w*a.z+a.x*a.y),1-2*(a.x*a.x+a.z*a.z))))
    end
end
local Quaternion={Inverse=function(a)return q(-a.x,-a.y,-a.z,a.w)end}
function Quaternion.Euler(x,y,z)
    x,y,z=math.rad(x)/2,math.rad(y)/2,math.rad(z)/2
    return q(0,math.sin(y),0,math.cos(y))*q(math.sin(x),0,0,math.cos(x))*q(0,0,math.sin(z),math.cos(z))
end
Quaternion.identity=q(0,0,0,1)
local function mul(a,b)return v(a.x*b.x,a.y*b.y,a.z*b.z)end
local function div(a,b)return v(a.x/b.x,a.y/b.y,a.z/b.z)end
local function transform()
    local t={_localPosition=v(0,0,0),_localRotation=Quaternion.identity,localScale=v(1,1,1)}
    setmetatable(t,{
        __index=function(self,k)
            local parent=rawget(self,'parent')
            if k=='localRotation' then return self._localRotation end
            if k=='rotation' then return parent and parent.rotation*self._localRotation or self._localRotation end
            if k=='eulerAngles' then return self.rotation.eulerAngles end
            if k=='lossyScale' then return parent and mul(parent.lossyScale,self.localScale) or self.localScale end
            if k=='localPosition' then return self._localPosition end
            if k=='position' then return parent and parent.position+parent.rotation*mul(parent.lossyScale,self._localPosition) or self._localPosition end
        end,
        __newindex=function(self,k,value)
            local parent=rawget(self,'parent')
            if k=='localRotation' then
                if (self==head and failHeadRestore) or (self==neck and failNeckRestore) then error('injected head restoration failure')end
                self._localRotation=value
            elseif k=='rotation' then self._localRotation=parent and Quaternion.Inverse(parent.rotation)*value or value
            elseif k=='eulerAngles' then self.rotation=Quaternion.Euler(value.x,value.y,value.z)
            elseif k=='localPosition' then self._localPosition=value
            elseif k=='position' then self._localPosition=parent and div(Quaternion.Inverse(parent.rotation)*(value-parent.position),parent.lossyScale) or value
            else rawset(self,k,value) end
        end})
    function t:SetParent(parent,worldStays)
        local pos,rot=self.position,self.rotation
        self.parent=parent
        if worldStays then self.position=pos;self.rotation=rot end
    end
    function t:SetPositionAndRotation(pos,rot) self.position=pos;self.rotation=rot end
    function t:Equals(other) return self==other or (other==nil and self.destroyed) end
    function t:IsChildOf(parent) return self==parent or (self.parent and self.parent:IsChildOf(parent)) or false end
    return t
end
local function alive(self,other) return self==other or (other==nil and rawget(self,'destroyed')==true) end
objects,errors,updates,registrations={}, {}, {}, 0
local function component(t) t.Equals=alive;return t end
local knownScan={'enabled','progress','centerPos','minDistance','maxDistance','width','interval','smoothness','maxFade',
    'color','distortIntensity','charBrightIntensity','highlightWidth','highlightThickness','colorHighlight'}
local Profile={}
function Profile:Add(type,overrides)
    assert(type=='HGScanLine' and overrides==false)
    if failScan then error('injected unavailable native ScanLine') end
    local scan=component({});for _,k in ipairs(knownScan) do
        local ranges={width={0,1},smoothness={1,50},maxFade={5,200},progress={0,50}}
        local range=ranges[k]
        if range then
            scan[k]=setmetatable({_value=0,overrideState=false},{
                __index=function(t,key)if key=='value' then return t._value end end,
                __newindex=function(t,key,n)if key=='value' then
                    assert(n>=range[1] and n<=range[2],'out of native range: '..k);rawset(t,'_value',n)
                else rawset(t,key,n) end end})
        else scan[k]={value=0,overrideState=false} end
    end
    setmetatable(scan,{__index=function(_,k)error('Unknown scan field '..k)end})
    self.scan=scan;return scan
end
local function go(name)
    local o=component({name=name,transform=transform(),activeSelf=true,components={}})
    objects[#objects+1]=o
    function o:SetActive(value)self.activeSelf=value end
    function o:AddComponent(type)
        local c=component({gameObject=self,transform=self.transform})
        if type=='CinemachineVirtualCamera' then
            c.m_Lens={NearClipPlane=.1,FarClipPlane=1000,FieldOfView=60}
            function c:SetFieldOfView(n)self.m_Lens.FieldOfView=n end
            function c:ForceCameraPosition(p,r)self.transform:SetPositionAndRotation(p,r)end
        elseif type=='Volume' then
            c.enabled=true
            function c:SetInstantiatedProfile(profile)self.profileRef=profile end
            function c:Play()self.vfxEnableState=true end
            function c:Stop()self.vfxEnableState=false end
            setmetatable(c,{__index=function(_,k)if k=='profile' then error('profile API not in current client')end end})
        elseif type=='RectTransform' then c=self.transform
        elseif type~='Canvas' and type~='RawImage' then error('Unknown component '..tostring(type)) end
        self.components[type]=c;return c
    end
    return o
end
local Vector3=setmetatable({Lerp=function(a,b,t)return a+(b-a)*t end},{__call=function(_,...)return v(...)end})
local Vector2=setmetatable({zero={x=0,y=0}},{__call=function(_,x,y)return {x=x,y=y}end})
local Texture2D=setmetatable({whiteTexture=component({name='Builtin White'})},{__call=function(_,w,h,format,mips)
    assert(format==1 and mips==false)
    local t=component({width=w,height=h,pixels={}});objects[#objects+1]=t
    function t:SetPixel(x,y,color) assert(not self.applied);self.pixels[y*w+x]=color end
    function t:Apply(mips,unreadable)assert(mips==false and unreadable==true);self.applied=true end
    return t
end})
CS={UnityEngine={Vector3=Vector3,Quaternion=Quaternion,Vector2=Vector2,
    Vector4=function(x,y,z,w)return {x=x,y=y,z=z,w=w}end,
    Color=function(r,g,b,a)return {r=r,g=g,b=b,a=a}end,
    GameObject=go,Canvas='Canvas',RenderMode={ScreenSpaceOverlay=1},RectTransform='RectTransform',Renderer='Renderer',
    UI={RawImage='RawImage'},HumanBodyBones={Head=1,Neck=2},Application={isFocused=true},Time={frameCount=0},
    Screen={width=1920,height=1080},Texture2D=Texture2D,TextureFormat={RGBA32=1},TextureWrapMode={Clamp=1},FilterMode={Bilinear=1},
    Rendering={ShadowCastingMode={Off=0,On=1,ShadowsOnly=3},Volume='Volume',VolumeProfile='VolumeProfile'},
    ScriptableObject={CreateInstance=function(type)assert(type=='VolumeProfile');return setmetatable(component({}),{__index=Profile})end},
    Object={Destroy=function(o)o.destroyed=true;if rawget(o,'activeSelf')~=nil then o.activeSelf=false end end}},
    Cinemachine={CinemachineVirtualCamera='CinemachineVirtualCamera'},HG={Rendering={Runtime={HGScanLine='HGScanLine'}}}}
typeof=function(t)return t end
local cam=component({transform=transform(),fieldOfView=60,nearClipPlane=.2,farClipPlane=1000})
cam.transform.rotation=Quaternion.Euler(0,0,0)
local level=component({name='Level',virtualCamera=component({name='Native Virtual'})});baseLevel=level
level.param={SetHorizontalAngle=function(_,yaw,tween)assert(tween==false);nativeYaw=yaw end}
local brain=component({IsBlending=false,ActiveVirtualCamera=level.virtualCamera})
function brain:SetCameraOverride(id,a,b,weight,dt)
    assert(a==nil and weight==1 and b.m_Lens)
    if id==-1 then self.serial=(self.serial or 0)+1;id=self.serial end
    self.override=id;self.ActiveVirtualCamera=b;return id
end
function brain:ReleaseCameraOverride(id)
    if failRemove then error('injected removal failure')end
    assert(id==self.override);self.override=nil
    if not foreignOverride then self.ActiveVirtualCamera=level.virtualCamera end
end
local mgr={mainCamera=cam,virtualCamsRoot=transform(),curActiveController=level,cinemachineBrainCpt=brain}
function mgr:IsCommonTempControllerActive()return false end
function mgr:GetMainLevelCameraController()return level end
function mgr:GetMainCameraVolumeLayerMask()return 2^8 end
neck=transform();neck.name='Bip001_Neck';neck.position=v(0,1.4,0)
head=transform();head.position=v(0,1.6,0);head:SetParent(neck,true)
render1=component({name='body',transform=transform(),shadowCastingMode=1});render2=component({name='hair',transform=transform(),shadowCastingMode=0})
local model=transform();function model:GetComponentsInChildren(type,include)assert(type=='Renderer' and include);return {[0]=render1,[1]=render2,Length=2}end
local body=transform()
rootCom=setmetatable({transform=body,model=model,replicatedCharInfo={templateId='chr_0027_tangtang'}},{__newindex=function(t,k,value)
    if k=='rotation' then t.transform.rotation=value;t.transform.eulerAngles=value.eulerAngles;turns=(turns or 0)+1 else rawset(t,k,value)end
end})
character={alive=true,inCinematic=false,rootCom=rootCom,
    animatorCom={animator=component({isHuman=true,GetBoneTransform=function(_,bone)assert(bone==1 or bone==2);return bone==1 and head or (not missingNeck and neck or nil) end})},
    movementComponent={enabled=true,isClimbing=false,inSkillAir=false},IsValid=function()return true end}
rotator={currentHandleId=0,isRotating=false,lockToCamera=false}
function rotator:RotateTo()error('rotation-only path forbidden in animated mode')end
function rotator:StopRotate()error('must not stop foreign rotation requests')end
character.rotateCom=rotator
character.movementComponent.isInAir=false
character.movementComponent.input={moveVector=v(0,0,0)}
function character.movementComponent:IsInStrafe()return strafe==true end
local modifierType='OverridableValue<RootMotionModifier>'
function newModifierStack()
    local storage={}
    local nodes=setmetatable({}, {__index=function(_,k)if k=='Count' then return #storage end;return storage[k+1] end})
    local stack={m_overrideValues=nodes,base={scale=1,disableCliffCheck=false}}
    function stack:GetType()return modifierType end
    function stack:GetValue()return #storage>0 and storage[#storage].value or self.base end
    function stack:SetOverride(id,value)
        for _,node in ipairs(storage)do if node.id==id then node.value=value;return end end
        storage[#storage+1]={id=id,value=value}
    end
    function stack:RemoveOverride(id)
        if failModifierRemove then error('injected modifier cleanup failure')end
        for i,node in ipairs(storage)do if node.id==id then table.remove(storage,i);return end end
    end
    return stack
end
character.movementComponent.rootMotionModifier=newModifierStack()
function character.movementComponent:AddRootMotionModifier(id,scale,disableCliffCheck)
    self.rootMotionModifier:SetOverride(id,{scale=scale,disableCliffCheck=disableCliffCheck})
    if failModifierAdd then error('injected partial modifier install failure')end
end
local function newTurnAction()
    local a={isActive=false,enabled=true,m_remainingCd=0}
    function a:Init(pivot,data) self.pivot=pivot;self.data=data end
    function a:_CalcExpectedGait(vec)assert(vec==character.movementComponent.input.moveVector);return 'Walk' end
    function a:_GetDuration(gait)assert(gait=='Walk');return self.data.duration end
    function a:_GetCurveTotalAngle()return self.data.total end
    function a:_GetRotationCurve()return self.data.curve end
    function a:_Start(delta,direction,gait,strict)
        if failNativeTurn then error('native animation API unavailable')end
        assert(not strict and gait=='Walk' and self.pivot.m_turnStartMove==self)
        self.delta=delta;self.direction=direction;self.startYaw=rootCom.transform.eulerAngles.y;self.time=0
        self.isActive=true;nativeRequests=(nativeRequests or 0)+1;animationStarts=(animationStarts or 0)+1
    end
    function a:Stop()
        if failNativeStop then error('injected native stop failure')end
        if self.isActive then nativeStops=(nativeStops or 0)+1 end
        self.isActive=false
    end
    return a
end
pivot={m_pivotData={duration=.4,total=90,curve=true},m_turnStartMove=newTurnAction(),isPivoting=false}
function pivot:_CanStartPivotOrTurnStart()return not blockNativeGate end
function pivot:_IsTurnStartDisabled()return disableTurnStart==true end
character.charPivotCom=pivot
CS.Beyond={Gameplay={View={Animation={CharacterPivotComponent='CharacterPivotComponent',CharacterTurnStartMove=newTurnAction}}}}
xlua={private_accessible=function(t)assert(t=='CharacterPivotComponent' or t==newTurnAction or t==modifierType);privateAccessCount=(privateAccessCount or 0)+1 end}
function nativeTurnTick(dt)
    local a=pivot.m_turnStartMove
    if not a.isActive or freezeNativeTurn then return end
    a.time=a.time+dt;local progress=math.min(1,a.time/a.data.duration)
    local body=rootCom.transform
    body.rotation=Quaternion.Euler(0,a.startYaw+a.delta*(progress*progress*(3-2*progress)),0)
    body.eulerAngles=body.rotation.eulerAngles
    body.position=body.position+v(character.movementComponent.rootMotionModifier:GetValue().scale*.3*dt,0,platformMotion and dt or 0)
    if progress==1 then a.isActive=false end
end
GameInstance={playerController={mainCharacter=character,blockPlayerInput=false,castingNormalAttack=false},cameraManager=mgr,isInGameplay=true}
InputManager={cursorVisible=false};InputManagerInst={GetAxis=function(_,name)return name=='Mouse X' and (mouseX or 0) or (mouseY or 0) end}
DeviceInfo={usingKeyboard=true,usingController=false};LuaSystemManager={factory={inTopView=false}}
UIUtils={IsPhaseLevelOnTop=function()return not menuOpen end}
Utils={isInCustomAbility=function()return customAbility==true end}
local n=0
LuaUpdate={Add=function(_,group,fn)n=n+1;updates[n]={group=group,fn=fn};return n end,
    Remove=function(_,id)updates[id]=nil;return -1 end}
local subscribe
local api={get=function(id)assert(id=='first-person-remix');return config end,
    subscribe=function(id,fn)assert(id=='first-person-remix');subscribe=fn;return function()subscribe=nil end end,
    report=function(id,event)assert(id=='first-person-remix');events=events or {};events[#events+1]=event;return true end}
function change(key,value)config[key]=value;if subscribe then subscribe(key,value,config,false)end end
function runGroup(group,dt)if group=='Tick' then CS.UnityEngine.Time.frameCount=CS.UnityEngine.Time.frameCount+1;nativeTurnTick(dt) end;local list={};for k,row in pairs(updates)do if row.group==group then list[#list+1]=row.fn end end;for _,fn in ipairs(list)do fn(dt)end end
testApi=api
LuaManagerInst={LoadLua=function(_,path)assert(path=='ZML/Api');return 'return testApi' end}
require_ex=function()end
logger={error=function(s)errors[#errors+1]=s end}
ZMLKeybinds={api=1,find=function()return nil end,register=function(id,def)
    assert(id=='first-person-remix' and def.primary=='Ctrl+F5');registrations=registrations+1
    return {pressed=function()local v=pressToggle;pressToggle=false;return v==true end}
end}
function approximate(a,b,tolerance)assert(math.abs(a-b)<(tolerance or .001),tostring(a)..' != '..tostring(b))end
