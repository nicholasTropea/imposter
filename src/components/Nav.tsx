import styles from '../styles/Nav.module.scss';

import  { Flex, Button } from 'antd';
import { 
    HomeOutlined,
    SkinOutlined,
    UsergroupAddOutlined,
    SettingOutlined
} from '@ant-design/icons'; 


const Nav = () => {
    return (
        <Flex
            className = { styles.nav }
            align = 'center'
            justify = 'space-around'
        >
            <Button icon = { <HomeOutlined /> } size = 'small'>HOME</Button>
            <Button icon = { <SkinOutlined /> } size = 'small'>SKINS</Button>
            <Button icon = { <UsergroupAddOutlined /> } size = 'small'>FRIENDS</Button>
            <Button icon = { <SettingOutlined /> } size = 'small'>SETTINGS</Button>
        </Flex>
    );
}

export default Nav;