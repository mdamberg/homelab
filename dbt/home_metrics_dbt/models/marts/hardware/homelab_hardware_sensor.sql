/*
    Mart level wrapper for hardware sensors that is 
    exposed to LightDash
*/

select  
    *
from  {{ ref('fct_hardware_sensor') }}