local U=CS.UnityEngine
local V,Q=U.Vector3,U.Quaternion
local R=U.Rendering
local ID='first-person'
assert(not rawget(_G,'ZMLFirstPerson'),'first-person namespace occupied')
local function live(o) return o~=nil and not o:Equals(nil) end
local function copy(v) return V(v.x,v.y,v.z) end
local function angle(x) return (x+180)%360-180 end
local function near(a,b) return math.abs(a-b)<.001 end
local function own(l,o)
    assert(o,'owned resource unavailable');l.objects[#l.objects+1]=o;return o
end
local function object(l,name) return own(l,U.GameObject(name)) end
local function settingsApi()
    local f=assert(loadstring(LuaManagerInst:LoadLua('ZML/Api'),'@ZML/Api'))
    return f()
end
local api=settingsApi()
local function reportEvent(event,err)
    pcall(api.report,ID,event)
    if err then pcall(function() logger.error('ZML FirstPerson: '..event..': '..tostring(err):gsub('[%c]',' '):sub(1,384)) end) end
end
local P={report=reportEvent}
local action,M,owner,unsubscribe,keys,cleanupKey
local function ensureKeys()
    require_ex('Common/Utils/UIUtils')
    if not rawget(_G,'ZMLKeybinds') then require_ex('UI/Panels/GameSetting/GameSettingCtrl') end
    local k=assert(rawget(_G,'ZMLKeybinds'),'keybinds dependency unavailable')
    assert(k.api==1,'keybinds version unavailable')
    if k._attachGate then k._attachGate() end
    action=k.find(ID,'toggle') or assert(k.register(ID,{id='toggle',name='第一人称 · 切换视角',primary='Ctrl+F5',secondary='None'}))
    assert(type(action.pressed)=='function','keybinds continuous input API required')
end
function P.pressed() return action and action.pressed() or false end
function P.character(relaxCinematic)
    local pc=GameInstance.playerController
    local ch=pc and pc.mainCharacter
    if not ch or not ch:IsValid() or not ch.alive then return nil end
    if ch.inCinematic and not relaxCinematic then return nil end
    return ch
end
local VIEW_GATES={'focus','gameplay','blocked_input','cursor','phase_level','top_view','ability','temp_camera','controller','blending','active_camera'}
local RELAX_FIELDS={blocked_input='relax_blocked_input',cursor='relax_cursor',phase_level='relax_phase_level',temp_camera='relax_temp_camera',controller='relax_controller',blending='relax_controller',active_camera='relax_controller'}
local lastDiagnostic=nil
local function emit(text)
    if text==lastDiagnostic then return end
    lastDiagnostic=text
    pcall(api.report,ID,text)
end
local function viewGates(l)
    local pc=GameInstance.playerController
    local mgr=GameInstance.cameraManager
    local level=mgr and mgr:GetMainLevelCameraController()
    local brain=mgr and mgr.cinemachineBrainCpt
    local active=live(brain) and brain.ActiveVirtualCamera or nil
    local tempCamera=false
    if mgr~=nil then tempCamera=not mgr:IsCommonTempControllerActive() end
    return {
        focus=U.Application.isFocused,
        gameplay=GameInstance.isInGameplay,
        blocked_input=not pc.blockPlayerInput,
        cursor=not InputManager.cursorVisible,
        phase_level=UIUtils.IsPhaseLevelOnTop(),
        top_view=not LuaSystemManager.factory.inTopView,
        ability=not Utils.isInCustomAbility(),
        temp_camera=tempCamera,
        controller=mgr~=nil and level~=nil and mgr.curActiveController==level,
        blending=live(brain) and not brain.IsBlending,
        active_camera=live(brain) and level~=nil and (active==level.virtualCamera or
            (l and live(l.virtual) and active==l.virtual and not l.releasing)),
    }
end
function P.allowed(ch,c)
    local g=viewGates(M.lease)
    local miss
    for _,k in ipairs(VIEW_GATES) do
        local f=RELAX_FIELDS[k]
        if not g[k] and not (c and f and c[f]) then miss=k;break end
    end
    if c==nil or c.diagnose_view_gates~=false then emit(miss and ('gate_'..miss) or 'gate_open') end
    return miss==nil
end
P.diagnose=emit
emit('boot')
local function charTag(ch)
    local s=''
    pcall(function()
        if not ch then return end
        local t
        pcall(function()
            local info=ch.root and ch.root.replicatedCharInfo
            t=info and info.templateId
        end)
        if t==nil then pcall(function() t=ch.characterId or ch.charId or ch.name end) end
        if t~=nil then s=(tostring(t):lower():gsub('[^a-z0-9]','')) end
    end)
    if s=='' then s='nil' end
    return s:sub(1,14)
end
function P.capture(ch)
    emit('cap_'..charTag(ch))
    local root=assert(ch.rootCom,'character root unavailable')
    local animator=assert(ch.animatorCom and ch.animatorCom.animator,'character animator unavailable')
    local grounder=ch.characterAnimCom and ch.characterAnimCom.grounderIK
    local refs=grounder and grounder.ik and grounder.ik.references
    local head=refs and refs.head
    if not live(head) and animator.isHuman then head=animator:GetBoneTransform(U.HumanBodyBones.Head) end
    assert(live(head) and live(root.transform),'head bone unavailable')
    local neck=animator.isHuman and animator:GetBoneTransform(U.HumanBodyBones.Neck) or nil
    if not live(neck) and live(head.parent) and head.parent.name=='Bip001_Neck' then neck=head.parent end
    if not live(neck) or neck==head or neck==root.transform or not head:IsChildOf(neck) then neck=nil end
    local mgr=assert(GameInstance.cameraManager,'camera manager unavailable')
    local cam=assert(mgr.mainCamera,'main camera unavailable')
    local e=cam.transform.eulerAngles
    local base=Q.Inverse(root.transform.rotation)*head.rotation
    local neutral=Q.Inverse(root.transform.rotation)*(head.position-root.transform.position)
    assert(neutral.y>.2 and neutral.y<4,'head height outside supported rig')
    return {character=ch,root=root,head=head,neck=neck,baseNeck=neck and Q.Inverse(root.transform.rotation)*neck.rotation,manager=mgr,originalController=mgr:GetMainLevelCameraController(),
        camera=cam,brain=assert(mgr.cinemachineBrainCpt),originalFov=cam.fieldOfView,originalNear=cam.nearClipPlane,
        objects={},renderers={},neutral=neutral,baseHead=base,localEye=copy(neutral),yaw=e.y,pitch=angle(e.x)}
end
function P.id(l)
    local data=l.root.replicatedCharInfo
    if data then return data.templateId end
    return nil
end
local function refreshRig(l)
    local ch=l.character
    if not ch or not live(l.root) then return false end
    local ok=pcall(function()
        local animator=ch.animatorCom and ch.animatorCom.animator
        local grounder=ch.characterAnimCom and ch.characterAnimCom.grounderIK
        local refs=grounder and grounder.ik and grounder.ik.references
        local head=refs and refs.head
        if not live(head) and animator and animator.isHuman then
            head=animator:GetBoneTransform(U.HumanBodyBones.Head)
        end
        if not live(head) then return false end
        local rt=l.root.transform
        local neck=animator and animator.isHuman and animator:GetBoneTransform(U.HumanBodyBones.Neck) or nil
        if not live(neck) and live(head.parent) and head.parent.name=='Bip001_Neck' then neck=head.parent end
        if not live(neck) or neck==head or neck==rt or not head:IsChildOf(neck) then neck=nil end
        l.head=head
        l.neck=neck
        l.baseHead=Q.Inverse(rt.rotation)*head.rotation
        l.baseNeck=neck and Q.Inverse(rt.rotation)*neck.rotation
        l.neutral=Q.Inverse(rt.rotation)*(head.position-rt.position)
        l.localEye=copy(l.neutral)
        l.headScaleOwned=false
        l.headRotationOwned=false
        l.neckRotationOwned=false
        l.headWarned=false
        return true
    end)
    if ok then emit('rig_'..math.floor(l.neutral.y*100)) end
    return ok
end
local function rendererSettings(l,c)
    local mode=c.hide_self and (c.show_body and 'head' or 'full') or 'none'
    local model=live(l.root) and l.root.model or nil
    local rescan=false
    if model and l.capturedModel~=model then rescan=true end
    if model and not rescan and l.rendererCaptured then
        local now=U.Time.realtimeSinceStartup
        if not l.nextScan or now>=l.nextScan then
            l.nextScan=now+.5
            local ok,arr=pcall(function() return model:GetComponentsInChildren(typeof(U.Renderer),true) end)
            if ok and arr then
                local first=l.renderers[1] and l.renderers[1].object
                if arr.Length~=#l.renderers or (first~=nil and arr[0]~=first) then
                    emit('rescan_'..#l.renderers..'_'..arr.Length)
                    rescan=true
                end
            else
                emit('rescan_fail')
            end
        end
    end
    if model and rescan then
        local owned=0
        for _,r in ipairs(l.renderers) do
            if r.owned and live(r.object) then pcall(function() r.object.shadowCastingMode=r.original end);owned=owned+1 end
        end
        if l.headScaleOwned and live(l.head) then pcall(function() l.head.localScale=l.headScaleOriginal end) end
        l.renderers={}
        l.rendererCaptured=false
        l.visualMode=nil
        l.capturedModel=model
        emit('mdl_new_'..owned)
        refreshRig(l)
    end
    if l.visualMode==mode then return end
    if mode~='none' then
        if not l.rendererCaptured then
            assert(live(model),'character render model unavailable')
            local renderers=model:GetComponentsInChildren(typeof(U.Renderer),true)
            local total=renderers.Length
            local hits,geom=0,0
            local rigY=(l.neutral and l.neutral.y) or 1.2
            for i=0,total-1 do
                local r=renderers[i]
                local name=(r.name or ''):lower()
                local headOnly=r.transform:IsChildOf(l.head) or name:find('face',1,true) or
                    name:find('hair',1,true) or name:find('head',1,true)
                if not headOnly then
                    local ok,y=pcall(function()
                        return l.root.transform:InverseTransformPoint(r.bounds.center).y
                    end)
                    if ok and type(y)=='number' and y>rigY*1.05 then headOnly=true;geom=geom+1 end
                end
                if headOnly then hits=hits+1 end
                l.renderers[#l.renderers+1]={object=r,original=r.shadowCastingMode,headOnly=headOnly and true or false}
            end
            l.rendererCaptured=true
            emit('rs_'..mode..'_'..hits..'g'..geom..'_'..total)
        end
    end
    for _,r in ipairs(l.renderers) do
        local hide=mode=='full' or (mode=='head' and r.headOnly)
        if live(r.object) then
            if r.owned and not hide and r.object.shadowCastingMode==R.ShadowCastingMode.ShadowsOnly then
                r.object.shadowCastingMode=r.original;r.owned=false
            elseif hide and not r.owned then
                r.original=r.object.shadowCastingMode
                r.object.shadowCastingMode=R.ShadowCastingMode.ShadowsOnly;r.owned=true
            end
        end
    end
    l.visualMode=mode
    if not l.tagged then
        l.tagged=true
        local nm='?'
        pcall(function() nm=(tostring(l.character and l.character.name or '?'):lower():gsub('[^a-z0-9]','')) end)
        emit('tag_'..charTag(l.character)..'_'..nm:sub(1,20))
    end
end
local function sameVector(a,b)
    return math.abs(a.x-b.x)<1e-6 and math.abs(a.y-b.y)<1e-6 and math.abs(a.z-b.z)<1e-6
end
local function restoreHead(l)
    if not l.headScaleOwned then return end
    if live(l.head) and sameVector(l.head.localScale,l.headScaleApplied) then
        l.head.localScale=l.headScaleOriginal
    end
    l.headScaleOwned=false
end
local function sameRotation(a,b)
    local d=math.abs(a.x*b.x+a.y*b.y+a.z*b.z+a.w*b.w)
    return math.abs(1-d)<1e-6
end
local function restoreLookBone(l,prefix,bone)
    if not l[prefix..'Owned'] then return end
    local applied=l[prefix..'Applied']
    if live(bone) and applied and sameRotation(bone.localRotation,applied) then
        bone.localRotation=l[prefix..'Original']
    end
    l[prefix..'Owned']=false
end
local function restoreHeadLook(l)
    restoreLookBone(l,'headRotation',l.head)
    restoreLookBone(l,'neckRotation',l.neck)
end

function P.resetHeadBinding(l)
    restoreHead(l)
    restoreHeadLook(l)
    if live(l.virtual) and l.virtual.transform.parent==l.head then
        l.virtual.transform:SetParent(l.manager.virtualCamsRoot,true)
    end
end
local function hideHeadForRender(l,c)
    if not c.hide_self or not c.show_body then restoreHead(l);return end
    if not live(l.head) then
        if not l.headWarned then l.headWarned=true;emit('head_dead') end
        return
    end
    if not live(l.root) then return end
    if not l.headScaleOwned then
        l.headScaleOriginal=copy(l.head.localScale)
        l.headScaleApplied=l.headScaleOriginal*.001
        l.headScaleOwned=true
    end
    l.head.localScale=l.headScaleApplied
end
function P.install(l,c)
    local go=object(l,'ZML FirstPerson Camera')
    go.transform:SetParent(l.manager.virtualCamsRoot,false)
    l.virtual=assert(go:AddComponent(typeof(CS.Cinemachine.CinemachineVirtualCamera)),'virtual camera unavailable')
    l.virtual.Priority=-100
    local lens=l.virtual.m_Lens
    lens.NearClipPlane=.035;lens.FarClipPlane=l.camera.farClipPlane;lens.FieldOfView=c.fov
    l.virtual.m_Lens=lens
    P.pose(l,l.yaw,l.pitch,c,0)
    l.overrideId=l.brain:SetCameraOverride(-1,nil,l.virtual,1,0)
    assert(type(l.overrideId)=='number' and l.overrideId>=0,'camera override rejected')
    l.activationFrame=U.Time.frameCount
    l.installed=true
    rendererSettings(l,c)
    reportEvent('entered')
end
function P.ownsCamera(l,relax)
    if l.overrideId==nil or not live(l.virtual) then return false end
    if l.manager.curActiveController~=l.originalController then return relax==true end
    return l.brain.ActiveVirtualCamera==l.virtual or
        (U.Time.frameCount==l.activationFrame and l.brain.ActiveVirtualCamera==l.originalController.virtualCamera)
end
function P.bodyYaw(l) return l.root.transform.eulerAngles.y end
function P.canTurn(l)
    local pc=GameInstance.playerController
    local m=l.character.movementComponent
    return m and m.enabled and not pc.blockPlayerInput and not pc.castingNormalAttack and
        not l.character.inCinematic and not m.isClimbing and not m.inSkillAir
end
local stepAccess=false
local function stepTypes()
    local A=CS.Beyond.Gameplay.View.Animation
    if not stepAccess then
        assert(xlua and type(xlua.private_accessible)=='function','xLua private access unavailable')
        xlua.private_accessible(typeof(A.CharacterPivotComponent))
        xlua.private_accessible(typeof(A.CharacterTurnStartMove))
        stepAccess=true
    end
    return A
end
local modifierTypes={}
local function modifierNodes(modifiers)
    local t=modifiers:GetType()
    if not modifierTypes[t] then xlua.private_accessible(t);modifierTypes[t]=true end
    return assert(modifiers.m_overrideValues,'native root-motion overrides unavailable')
end
local function modifierNode(modifiers,id)
    local nodes=modifierNodes(modifiers)
    for i=0,nodes.Count-1 do
        local node=nodes[i]
        if node.id==id then return node end
    end
end
local function suppressTurnTranslation(lease)
    local mover=lease.mover
    local modifiers=assert(mover.rootMotionModifier,'native root-motion modifier unavailable')
    local id=0x5a4d4c46
    while modifierNode(modifiers,id) do
        id=id+1;assert(id<0xffffffff,'native modifier key exhausted')
    end
    lease.translation={owner=modifiers,id=id}
    mover:AddRootMotionModifier(id,0,false)
    lease.translation.node=assert(modifierNode(modifiers,id),'native modifier rejected')
    assert(modifiers:GetValue().scale==0,'native translation suppression rejected')
end
local function restoreTurnTranslation(lease)
    local translation=lease.translation
    if not translation then return end
    local node=modifierNode(translation.owner,translation.id)
    if node and (translation.node==nil or node==translation.node) and
        node.value.scale==0 and not node.value.disableCliffCheck then
        translation.owner:RemoveOverride(translation.id)
    end
    lease.translation=nil
end
function P.stopTurn(l)
    local lease=l.stepTurn
    if not lease then return end
    if l.character:IsValid() then
        restoreTurnTranslation(lease)
        lease.move:Stop()
        if lease.pivot.m_turnStartMove==lease.move then lease.pivot.m_turnStartMove=lease.original end
    end
    l.stepTurn=nil
end
function P.turn(l,yaw,c,targetYaw)
    if not c.native_body_turn then
        P.stopTurn(l)
        l.root.rotation=Q.Euler(0,yaw,0)
        return true
    end
    if l.nativeTurnUnavailable then return false end
    local ok,result=pcall(function()
        local A=stepTypes()
        local pivot=assert(l.character.charPivotCom,'native character pivot unavailable')
        local mover=l.character.movementComponent
        local rotator=assert(l.character.rotateCom,'native rotator unavailable')
        local lease=l.stepTurn
        if lease then
            if mover~=lease.mover or pivot~=lease.pivot or pivot.m_turnStartMove~=lease.move then
                P.stopTurn(l);return false
            end
            if not lease.move.isActive or mover.isInAir or mover:IsInStrafe() or
                rotator.lockToCamera or GameInstance.playerController.hasMoveInput then P.stopTurn(l);return false end
            return true
        end
        if mover.isInAir or mover:IsInStrafe() or rotator.lockToCamera or rotator.isRotating or
            GameInstance.playerController.hasMoveInput then return false end
        if not pivot:_CanStartPivotOrTurnStart() or pivot:_IsTurnStartDisabled() or pivot.isPivoting then return false end
        local original=assert(pivot.m_turnStartMove,'native turn-start action unavailable')
        if not original.enabled or original.isActive or original.m_remainingCd>0 then return false end
        local data=assert(pivot.m_pivotData,'native turn animation curves unavailable')
        local move=A.CharacterTurnStartMove()
        move:Init(pivot,data);move.enabled=original.enabled
        local gait=move:_CalcExpectedGait(mover.input.moveVector)
        local duration,total=move:_GetDuration(gait),move:_GetCurveTotalAngle(gait)
        assert(duration>0 and duration<10 and math.abs(total)>0.01 and move:_GetRotationCurve(gait),
            'native turn animation curve invalid')
        local delta=angle(targetYaw-P.bodyYaw(l))
        if math.abs(delta)<=1 then return false end
        local direction=Q.Euler(0,targetYaw,0)*V(0,0,1)
        l.stepTurn={pivot=pivot,original=original,move=move,mover=mover}
        if c.turn_in_place then suppressTurnTranslation(l.stepTurn) end
        pivot.m_turnStartMove=move
        move:_Start(delta,direction,gait,false)
        assert(move.isActive,'native animated turn-start rejected')
        reportEvent('native_step_turn_started')
        return true
    end)
    if not ok then
        l.nativeTurnUnavailable=true
        pcall(P.stopTurn,l)
        reportEvent('native_turn_unavailable',result)
        return false
    end
    return result
end
local STABLE_TURN_LIMIT=25
local function stabilizeRotation(l,target,dt,c)
    local tau=c.rotation_smoothing or 0
    local frame=U.Time.frameCount
    if tau<=0 then
        l.stableRot=target;l.stableRotFrame=frame
        return target
    end
    if l.stableRot==nil then
        l.stableRot=target;l.stableRotFrame=frame
        return l.stableRot
    end
    if l.stableRotFrame==frame then return l.stableRot end
    l.stableRotFrame=frame
    local step=math.max(0,math.min(dt or 0,.1))
    if step<=0 then return l.stableRot end
    local dot=math.min(1,math.abs(l.stableRot.x*target.x+l.stableRot.y*target.y+l.stableRot.z*target.z+l.stableRot.w*target.w))
    if 2*math.acos(dot)*57.295779513>STABLE_TURN_LIMIT then
        l.stableRot=target
        return l.stableRot
    end
    l.stableRot=Q.Slerp(l.stableRot,target,1-math.exp(-step/tau))
    return l.stableRot
end
function P.pose(l,yaw,pitch,c,dt,postAnimation)
    assert(live(l.head) and live(l.root.transform) and live(l.virtual),'camera rig destroyed')
    restoreHeadLook(l)
    local body=l.root.transform
    if c.diagnose_view_gates then
        local be=body.eulerAngles
        local tilt=math.abs(angle(be.x))+math.abs(angle(be.z))
        if tilt>15 then
            local now=U.Time.realtimeSinceStartup
            if not l.poseT or now-l.poseT>=.2 then
                l.poseT=now
                local f=body.forward
                local flat=math.sqrt(f.x*f.x+f.z*f.z)
                local flatYaw=flat>1e-3 and math.floor(math.deg(math.atan2(f.x,f.z))) or 999
                emit('pose_'..math.floor(angle(be.y))..'_'..math.floor(angle(be.x))..'_'..
                    math.floor(angle(be.z))..'_'..flatYaw..'_'..math.floor(yaw))
            end
        end
    end
    local localHead=Q.Inverse(body.rotation)*(l.head.position-body.position)
    local wanted=V(c.head_translation and localHead.x or l.neutral.x,
        c.height_variation and localHead.y or l.neutral.y,
        c.head_translation and localHead.z or l.neutral.z)
    if c.smoothing==0 then l.localEye=copy(wanted)
    elseif postAnimation then l.localEye=V.Lerp(l.localEye,wanted,1-math.exp(-dt/c.smoothing)) end
    local baseRotation=Q.Euler(pitch,yaw,0)
    local delta=Q.Inverse(body.rotation)*l.head.rotation*Q.Inverse(l.baseHead)
    local e=delta.eulerAngles
    local rotation
    if c.head_translation or c.head_look_binding then
        -- 真跟: 朝向由头骨世界姿态用四元数合成, 不做欧拉分解(空翻时会突跳)
        -- 低通只加在"动画偏移"这一段上, 鼠标输入不经过滤波, 所以平滑不会变成迟滞
        local offset=l.head.rotation*Q.Inverse(body.rotation*l.baseHead)
        local tau=c.rotation_smoothing or 0
        if tau>0 then
            local frame=U.Time.frameCount
            if l.animRot==nil then
                l.animRot=offset;l.animRotFrame=frame
            elseif l.animRotFrame~=frame then
                l.animRotFrame=frame
                local step=math.max(0,math.min(dt or 0,.1))
                if step>0 then l.animRot=Q.Slerp(l.animRot,offset,1-math.exp(-step/tau)) end
            end
            offset=l.animRot
        else
            l.animRot=offset
        end
        if not c.head_rotation then rotation=baseRotation
        elseif c.head_strength>=1 then rotation=offset*baseRotation
        else rotation=Q.Slerp(baseRotation,offset*baseRotation,c.head_strength) end
    else
        rotation=baseRotation*Q.Euler(c.head_rotation and angle(e.x)*c.head_strength or 0,
            c.head_rotation and angle(e.y)*c.head_strength or 0,c.head_tilt and angle(e.z)*c.head_strength or 0)
        rotation=stabilizeRotation(l,rotation,dt,c)
    end
    local eye=body.position+Q.Euler(0,body.eulerAngles.y,0)*l.localEye+V(0,c.eye_offset,0)+Q.Euler(0,yaw,0)*V(0,0,c.forward_offset)
    if c.head_look_binding then
        local headYaw=body.eulerAngles.y+math.max(-85,math.min(85,angle(yaw-body.eulerAngles.y)))
        local aim=Q.Euler(pitch,headYaw,0)*Q.Euler(c.head_rotation and angle(e.x)*c.head_strength or 0,
            c.head_rotation and angle(e.y)*c.head_strength or 0,c.head_tilt and angle(e.z)*c.head_strength or 0)
        local posedHead=aim*l.baseHead
        local headPosition=l.head.position
        if live(l.neck) then
            local neckYaw=math.max(-40,math.min(40,angle(headYaw-body.eulerAngles.y)*.6))
            local neckPitch=math.max(-45,math.min(45,pitch*.6))
            local neckAim=Q.Euler(neckPitch,body.eulerAngles.y+neckYaw,0)*
                Q.Euler(c.head_rotation and angle(e.x)*c.head_strength*.6 or 0,
                    c.head_rotation and angle(e.y)*c.head_strength*.6 or 0,
                    c.head_tilt and angle(e.z)*c.head_strength*.5 or 0)
            local posedNeck=neckAim*l.baseNeck
            headPosition=l.neck.position+posedNeck*Q.Inverse(l.neck.rotation)*(headPosition-l.neck.position)
            if postAnimation then
                l.neckRotationOriginal=l.neck.localRotation
                l.neckRotationOwned=true
                l.neck.rotation=posedNeck
                l.neckRotationApplied=l.neck.localRotation
            end
        elseif not l.neckUnavailable then
            l.neckUnavailable=true;reportEvent('neck_binding_unavailable')
        end
        if postAnimation then
            l.headRotationOriginal=l.head.localRotation
            l.headRotationOwned=true
            l.head.rotation=posedHead
            l.headRotationApplied=l.head.localRotation
        end
        local headRotation=postAnimation and l.head.rotation or posedHead
        eye=(postAnimation and l.head.position or headPosition)+headRotation*Q.Inverse(l.baseHead)*V(0,c.eye_offset,c.forward_offset)
        if l.virtual.transform.parent~=l.head then l.virtual.transform:SetParent(l.head,true) end
    elseif l.virtual.transform.parent==l.head then
        l.virtual.transform:SetParent(l.manager.virtualCamsRoot,true)
    end
    l.virtual:SetFieldOfView(c.fov)
    l.virtual:ForceCameraPosition(eye,rotation)
    if l.overrideId then
        l.originalController.param:SetHorizontalAngle(yaw,false)
        local handle=l.brain:SetCameraOverride(l.overrideId,nil,l.virtual,1,dt)
        assert(handle==l.overrideId,'camera override handle changed')
    end
    l.lastPosition,l.lastRotation,l.lastFov=copy(eye),rotation,c.fov
    rendererSettings(l,c)
end
local function tail(dt)
    local l=M.lease
    local relax=M.settings and M.settings.relax_controller
    if M.holding then
        if not l or l.releasing or not live(l.camera) or not live(l.virtual) then return end
        relax=true
    elseif not l or l.releasing or not P.ownsCamera(l,relax) or not P.allowed(l.character,M.settings) then
        return
    end
    P.pose(l,M.yaw,M.pitch,M.settings,math.max(0,math.min(dt or 0,.1)),true)
    if relax or not l.manager.cinemachineBrainCpt.IsBlending then
        l.camera.transform:SetPositionAndRotation(l.lastPosition,l.lastRotation)
        l.camera.fieldOfView=M.settings.fov;l.camera.nearClipPlane=.035
        l.actualOwned=true
        hideHeadForRender(l,M.settings)
        if M.settings.head_look_binding then
            l.virtual:ForceCameraPosition(l.lastPosition,l.lastRotation)
        end
    end
end
local function overlay(l)
    if live(l.overlay) then return end
    local go=object(l,'ZML FirstPerson Vision')
    local canvas=go:AddComponent(typeof(U.Canvas))
    canvas.renderMode=U.RenderMode.ScreenSpaceOverlay;canvas.sortingOrder=-10
    local imageGo=object(l,'Vision Mask')
    local rect=imageGo:AddComponent(typeof(U.RectTransform))
    rect:SetParent(go.transform,false)
    rect.anchorMin=U.Vector2(0,0);rect.anchorMax=U.Vector2(1,1)
    rect.offsetMin=U.Vector2.zero;rect.offsetMax=U.Vector2.zero
    local image=imageGo:AddComponent(typeof(U.UI.RawImage));image.raycastTarget=false
    l.overlay,l.mask,l.maskRect=go,image,rect
    go:SetActive(false)
end
local function texture(l,w,h,pixel)
    local tex=own(l,U.Texture2D(w,h,U.TextureFormat.RGBA32,false))
    tex.wrapMode=U.TextureWrapMode.Clamp;tex.filterMode=U.FilterMode.Bilinear
    for y=0,h-1 do for x=0,w-1 do tex:SetPixel(x,y,pixel((x+.5)/w,(y+.5)/h)) end end
    tex:Apply(false,true)
    return tex
end
local function eyepatch(l)
    local aspect=U.Screen.width/math.max(1,U.Screen.height)
    if l.maskTexture and near(l.maskAspect,aspect) then return end
    local tex=texture(l,128,96,function(x,y) return U.Color(0,0,0,M.eyepatchAlpha(x,y,aspect)) end)
    local old=l.maskTexture
    l.maskTexture,l.maskAspect=tex,aspect
    if old then
        for i,o in ipairs(l.objects) do if o==old then table.remove(l.objects,i);break end end
        U.Object.Destroy(old)
    end
end
local function scanProjection(l)
    overlay(l)
    if l.scanTexture then return end
    l.scanTexture=texture(l,8,128,function(_,y)
        local a=math.exp(-((y-.5)/.13)^2)*.24
        return U.Color(.25,.9,1,a)
    end)
end
local function acceptedVolumeLayer(mask)
    assert(mask~=0,'main camera has no volume layers')
    for i=0,31 do if math.floor(mask/2^i)%2==1 then return i end end
    error('volume layer unavailable')
end
local function parameter(scan,key,value)
    local p=assert(scan[key],'scan render parameter missing: '..key)
    p.value=value;p.overrideState=true
end
local function scanVolume(l)
    if live(l.volume) then return end
    local go=object(l,'ZML FirstPerson Inhibitor Scan')
    go.layer=acceptedVolumeLayer(l.manager:GetMainCameraVolumeLayerMask())
    local volume=go:AddComponent(typeof(R.Volume));volume.enabled=false
    local profile=own(l,U.ScriptableObject.CreateInstance(typeof(R.VolumeProfile)))
    l.profile=profile
    local scan=profile:Add(typeof(CS.HG.Rendering.Runtime.HGScanLine),false)
    l.scan=own(l,scan)
    parameter(scan,'enabled',true)
    parameter(scan,'progress',0)
    parameter(scan,'minDistance',0);parameter(scan,'maxDistance',50)
    parameter(scan,'width',.6);parameter(scan,'interval',.1)
    parameter(scan,'smoothness',10);parameter(scan,'maxFade',40)
    parameter(scan,'color',U.Color(.2,.85,1,1))
    parameter(scan,'distortIntensity',.04);parameter(scan,'charBrightIntensity',.3)
    parameter(scan,'highlightWidth',1);parameter(scan,'highlightThickness',.15)
    parameter(scan,'colorHighlight',U.Color(.5,1,1,1))
    volume:SetInstantiatedProfile(profile)
    volume.isGlobal=true;volume.priority=100000;volume.weight=1
    l.volume=volume
end
function P.effects(l,effect,c,dt)
    if effect=='scan' then
        l.scanTime=((l.scanTime or 0)+dt)%c.scan_period
        scanProjection(l)
        local y=-.16+1.32*l.scanTime/c.scan_period
        l.maskRect.anchorMin=U.Vector2(0,y-.12);l.maskRect.anchorMax=U.Vector2(1,y+.12)
        l.mask.texture=l.scanTexture;l.mask.color=U.Color(1,1,1,1);l.overlay:SetActive(true)
    else l.scanTime=0 end
    if effect=='scan' and not l.scanFailed then
        local ok,err=pcall(function()
            scanVolume(l)
            parameter(l.scan,'progress',50*l.scanTime/c.scan_period)
            local p=l.root.transform.position
            parameter(l.scan,'centerPos',U.Vector4(p.x,p.y,p.z,1))
            l.volume.gameObject.layer=acceptedVolumeLayer(l.manager:GetMainCameraVolumeLayerMask())
            l.volume.enabled=true
            l.volume:Play()
        end)
        if not ok then
            l.scanFailed=true
            if live(l.volume) then l.volume.enabled=false end
            reportEvent('scan_render_unavailable',err)
        end
    elseif live(l.volume) then l.volume:Stop();l.volume.enabled=false end
    if effect=='eyepatch' or effect=='sunglasses' then
        overlay(l)
        l.maskRect.anchorMin=U.Vector2(0,0);l.maskRect.anchorMax=U.Vector2(1,1)
        if effect=='eyepatch' then
            eyepatch(l);l.mask.texture=l.maskTexture;l.mask.color=U.Color(1,1,1,1)
        else l.mask.texture=U.Texture2D.whiteTexture;l.mask.color=U.Color(0,0,0,c.sunglasses_darkness) end
        l.overlay:SetActive(true)
    elseif effect~='scan' and live(l.overlay) then l.overlay:SetActive(false) end
end
function P.release(l)
    l.releasing=true
    local success=true
    local restoreActual=false
    local function attempt(fn) if not pcall(fn) then success=false end end
    attempt(function() P.stopTurn(l) end)
    if l.actualOwned then attempt(function()
        if live(l.brain) then
            restoreActual=l.manager.curActiveController==l.originalController and
                (l.brain.ActiveVirtualCamera==l.virtual or l.brain.ActiveVirtualCamera==l.originalController.virtualCamera)
        end
    end) end
    attempt(function() P.resetHeadBinding(l) end)
    if live(l.volume) then attempt(function() l.volume:Stop();l.volume.enabled=false end) end
    if live(l.overlay) then attempt(function() l.overlay:SetActive(false) end) end
    for _,r in ipairs(l.renderers) do
        if r.owned then attempt(function()
            if live(r.object) and r.object.shadowCastingMode==R.ShadowCastingMode.ShadowsOnly then r.object.shadowCastingMode=r.original end
            r.owned=false
        end) end
    end
    if l.overrideId then attempt(function()
        if live(l.brain) then l.brain:ReleaseCameraOverride(l.overrideId) end
        l.overrideId=nil
    end) end
    if l.actualOwned then attempt(function()
        if restoreActual and live(l.camera) then
            if near(l.camera.nearClipPlane,.035) then l.camera.nearClipPlane=l.originalNear end
            if near(l.camera.fieldOfView,l.lastFov) then l.camera.fieldOfView=l.originalFov end
        end
        l.actualOwned=false
    end) end
    if success then
        for i=#l.objects,1,-1 do attempt(function()
            local o=l.objects[i];if live(o) then U.Object.Destroy(o) end;l.objects[i]=nil
        end) end
    end
    return success
end
M=ZMLFPFactory(P)
local function guarded(fn,...)
    local ok,err=pcall(fn,...)
    if not ok then M.fault(err) end
end
local function detach()
    for _,key in ipairs(keys or {}) do pcall(function() LuaUpdate:Remove(key) end) end;keys={}
    if unsubscribe then pcall(unsubscribe);unsubscribe=nil end
end
local function cleanupRetry()
    if not M.lease or cleanupKey then return end
    cleanupKey=LuaUpdate:Add('Tick',function()
        local ok,done=pcall(M.release)
        if ok and done then LuaUpdate:Remove(cleanupKey);cleanupKey=nil end
    end)
end
local holdTimer=nil
local function cancelHold()
    if holdTimer then pcall(function() LuaUpdate:Remove(holdTimer) end);holdTimer=nil end
end
local function releaseHold(reason)
    cancelHold()
    M.holding=false
    reportEvent(reason)
    detach();pcall(M.release);cleanupRetry()
end
local function hideFlags()
    local f=''
    pcall(function()
        local pc=GameInstance.playerController
        local ch=pc and pc.mainCharacter
        if ch and ch.inCinematic then f=f..'c' end
    end)
    pcall(function() if Utils.isInCustomAbility() then f=f..'a' end end)
    pcall(function() if not GameInstance.cameraManager:IsCommonTempControllerActive() then f=f..'t' end end)
    pcall(function()
        local m=GameInstance.cameraManager
        if m.curActiveController~=m:GetMainLevelCameraController() then f=f..'x' end
    end)
    pcall(function() if LuaSystemManager.factory.inTopView then f=f..'v' end end)
    pcall(function() if UIUtils.IsPhaseLevelOnTop() then f=f..'p' end end)
    if f=='' then f='none' end
    return f
end
local function alive(l)
    return l~=nil and not l.releasing and live(l.camera) and live(l.virtual) and
        live(l.originalController) and live(l.root)
end
local function holdPos()
    local ok,x,y,z=pcall(function()
        local pc=GameInstance.playerController
        local ch=pc and pc.mainCharacter
        local p=ch and ch.transform and ch.transform.position
        if not p then return nil end
        return p.x,p.y,p.z
    end)
    if ok and type(x)=='number' then return x,y,z end
end
local function armHold()
    cancelHold()
    local key,t0,acc,prev,reported
    key=LuaUpdate:Add('Tick',function()
        if owner~=nil then
            holdTimer=nil;M.holding=false
            pcall(function() LuaUpdate:Remove(key) end)
            return
        end
        if not alive(M.lease) then
            holdTimer=nil
            releaseHold('view_hide_lost')
            return
        end
        local raw
        pcall(function()
            local pc=GameInstance.playerController
            raw=pc and pc.mainCharacter
        end)
        if raw and M.lease.character and raw~=M.lease.character then
            holdTimer=nil
            releaseHold('hchg_'..charTag(raw))
            return
        end
        local now=pcall(function() return U.Time.realtimeSinceStartup end) and U.Time.realtimeSinceStartup or nil
        local x,y,z=holdPos()
        if prev and x then
            local dx,dy,dz=x-prev[1],y-prev[2],z-prev[3]
            acc=(acc or 0)+math.sqrt(dx*dx+dy*dy+dz*dz)
        end
        if x then prev={x,y,z} end
        if t0==nil and now then t0=now end
        if not reported and t0 and now and (now-t0)>=0.6 then
            reported=true
            local a=acc or 0
            reportEvent('hold2_'..hideFlags()..(a>3 and 'f' or (a>0.8 and 's' or 'n')))
        end
    end)
    holdTimer=key
end
function M.show(ctrl)
    cancelHold()
    if owner and owner~=ctrl then M.hide(owner) end
    owner=ctrl;M.holding=false;detach()
    local ok,err=pcall(function()
        ensureKeys()
        M.configure(assert(api.get(ID)))
        unsubscribe=api.subscribe(ID,function(_,_,values) guarded(M.configure,values) end)
        keys={LuaUpdate:Add('Tick',function(dt) guarded(function()
                if M.lease then restoreHead(M.lease);restoreHeadLook(M.lease) end
                M.frame(dt)
            end) end),
            LuaUpdate:Add('TailTick',function(dt) guarded(tail,dt) end)}
        reportEvent('ready')
    end)
    if not ok then detach();M.fault(err);cleanupRetry() end
end
function M.hide(ctrl)
    if owner~=ctrl then return end
    owner=nil
    if M.settings and M.settings.hold_on_view_hide then
        M.holding=true
        local rawCh
        pcall(function()
            local pc=GameInstance.playerController
            rawCh=pc and pc.mainCharacter
        end)
        reportEvent('hold_'..hideFlags()..'_'..charTag(rawCh))
        armHold()
        return
    end
    M.holding=false
    reportEvent('view_hide_released')
    detach();pcall(M.release);cleanupRetry()
end
function M.close(ctrl)
    if owner and owner~=ctrl then return end
    reportEvent('view_close')
    cancelHold();M.holding=false
    M.hide(ctrl);M.wanted=false;pcall(M.release);cleanupRetry()
end
function M.move(ctrl,delta)
    local relax=(M.settings and M.settings.relax_controller) or M.holding
    if not ctrl:CanMoveCam() or not M.lease or M.lease.releasing then return false end
    if not M.holding and not P.ownsCamera(M.lease,relax) then return false end
    if not M.holding and not P.allowed(M.lease.character,M.settings) then return false end
    local x,y=delta.x,delta.y
    if DeviceInfo.usingKeyboard then
        if x==0 then x=InputManagerInst:GetAxis('Mouse X')*.9 end
        if y==0 then y=InputManagerInst:GetAxis('Mouse Y')*.63 end
    elseif DeviceInfo.usingController then x=x*90;y=y*90 end
    local ok,result=pcall(M.look,x,y)
    if not ok then M.fault(result);return false end
    return result
end
_G.ZMLFirstPerson=M
return M
