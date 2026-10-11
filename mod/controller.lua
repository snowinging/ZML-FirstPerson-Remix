return function(P)
    local M={wanted=false, holding=false, settings=nil, lease=nil, failed=false, turning=false}
    local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
    local function angle(x) return (x+180)%360-180 end
    local function number(v,key,lo,hi)
        local x=tonumber(v[key]);assert(x and x==x and x>=lo and x<=hi,'invalid '..key);return x
    end
    local function bool(v,key) assert(v[key]=='true' or v[key]=='false','invalid '..key);return v[key]=='true' end
    function M.configure(v)
        local c={}
        for _,k in ipairs({'enabled','height_variation','head_translation','head_rotation','head_tilt','hide_self','show_body',
            'fun_effects','tangtang_patch','endmin_scan','dapan_sunglasses'}) do c[k]=bool(v,k) end
        for _,d in ipairs({{'fov',40,120},{'sensitivity',.2,8},{'head_strength',0,1},{'eye_offset',-.2,.3},
            {'forward_offset',0,.3},{'smoothing',0,.4},{'turn_speed',90,1080},{'scan_period',1,10},{'sunglasses_darkness',.05,.75}}) do
            c[d[1]]=number(v,d[1],d[2],d[3])
        end
        c.turn_threshold=v.turn_threshold==nil and 90 or number(v,'turn_threshold',0,180)
        c.rotation_smoothing=v.rotation_smoothing==nil and .015 or number(v,'rotation_smoothing',0,.1)
        for _,k in ipairs({'relax_blocked_input','relax_cursor','relax_phase_level','relax_temp_camera','relax_cinematic','relax_controller'}) do
            if v[k]==nil then c[k]=false else c[k]=bool(v,k) end
        end
        if v.diagnose_view_gates==nil then c.diagnose_view_gates=true else c.diagnose_view_gates=bool(v,'diagnose_view_gates') end
        if v.hold_on_view_hide==nil then c.hold_on_view_hide=true else c.hold_on_view_hide=bool(v,'hold_on_view_hide') end
        if v.native_body_turn==nil then c.native_body_turn=false else c.native_body_turn=bool(v,'native_body_turn') end
        if v.head_look_binding==nil then c.head_look_binding=false else c.head_look_binding=bool(v,'head_look_binding') end
        if v.turn_in_place==nil then c.turn_in_place=true else c.turn_in_place=bool(v,'turn_in_place') end
        if M.settings and (M.settings.native_body_turn~=c.native_body_turn or M.settings.turn_threshold~=c.turn_threshold or
            M.settings.turn_in_place~=c.turn_in_place) then
            if M.lease and P.stopTurn then P.stopTurn(M.lease);M.lease.nativeTurnUnavailable=nil end
            M.turning=false
        end
        if M.settings and M.settings.head_look_binding~=c.head_look_binding and M.lease and P.resetHeadBinding then
            P.resetHeadBinding(M.lease)
        end
        M.settings=c;M.failed=false
        if not c.enabled then M.wanted=false;M.release() end
    end
    function M.release()
        if not M.lease then return true end
        if P.release(M.lease) then M.lease=nil;M.turning=false;return true end
        return false
    end
    function M.toggle()
        if not M.settings or not M.settings.enabled then return end
        M.wanted=not M.wanted;M.failed=false
        if not M.wanted then M.release() end
    end
    function M.effect(id)
        local c=M.settings
        if not c.fun_effects then return 'none' end
        if id=='chr_0027_tangtang' and c.tangtang_patch then return 'eyepatch' end
        if (id=='chr_0002_endminm' or id=='chr_0003_endminf') and c.endmin_scan then return 'scan' end
        if id=='chr_0018_dapan' and c.dapan_sunglasses then return 'sunglasses' end
        return 'none'
    end
    function M.look(x,y)
        if not M.lease or M.lease.releasing then return false end
        assert(x==x and y==y and math.abs(x)<10000 and math.abs(y)<10000,'invalid camera input')
        M.yaw=angle(M.yaw+x*M.settings.sensitivity)
        M.pitch=clamp(M.pitch-y*M.settings.sensitivity,-80,80)
        return true
    end
    function M.frame(dt)
        if not M.settings then return end
        dt=clamp(tonumber(dt) or 0,0,.1)
        if P.pressed() then M.toggle() end
        if M.lease and M.lease.releasing then if not M.release() then return end end
        local ch=P.character(M.settings.relax_cinematic)
        if not ch and P.diagnose then
            local raw=GameInstance.playerController and GameInstance.playerController.mainCharacter
            if not raw or not raw:IsValid() then P.diagnose('gate_no_character')
            elseif not raw.alive then P.diagnose('gate_character_dead')
            elseif raw.inCinematic then P.diagnose('gate_cinematic') end
        end
        local allowed=ch and M.settings.enabled and M.wanted and not M.failed and P.allowed(ch,M.settings)
        if M.lease and not M.holding then
            local owned=P.ownsCamera(M.lease,M.settings.relax_controller)
            if allowed and P.diagnose then
                if M.lease.character~=ch then P.diagnose('gate_character_changed')
                elseif not owned then P.diagnose('gate_owns_camera') end
            end
            if not allowed or M.lease.character~=ch or not owned then
                if not M.release() then return end
            end
        end
        if not allowed and not M.holding then return end
        if not M.lease then
            if not ch then return end
            local l=P.capture(ch)
            M.lease=l
            M.yaw,M.pitch=l.yaw,l.pitch
            M.turning=false
            P.install(l,M.settings)
            if M.lease~=l or l.releasing then P.release(l);return end
        end
        local l=M.lease
        local body=P.bodyYaw(l)
        local delta=angle(M.yaw-body)
        if math.abs(delta)>M.settings.turn_threshold then M.turning=true end
        if M.turning and math.abs(delta)<=1 then M.turning=false end
        if M.turning and P.canTurn(l) and dt>0 then
            local step=clamp(delta,-M.settings.turn_speed*dt,M.settings.turn_speed*dt)
            local accepted=P.turn(l,angle(body+step),M.settings,M.yaw)
            if accepted==false then M.turning=false
            elseif not M.settings.native_body_turn and math.abs(delta-step)<1 then M.turning=false end
        elseif P.stopTurn then P.stopTurn(l) end
        if not M.turning and P.stopTurn then P.stopTurn(l) end
        P.pose(l,M.yaw,M.pitch,M.settings,dt)
        P.effects(l,M.effect(P.id(l)),M.settings,dt)
    end
    function M.fault(err)
        M.failed=true;M.wanted=false
        if M.lease then M.lease.releasing=true;pcall(M.release) end
        P.report('camera_failed',err)
    end
    M.angle=angle
    function M.eyepatchAlpha(x,y,aspect)
        local d=math.sqrt((x+.12)^2+((y-.5)/aspect)^2)
        local t=clamp((d-.43)/.17,0,1)
        return 1-t*t*(3-2*t)
    end
    return M
end
